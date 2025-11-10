
import subprocess
import win32event
import win32api
from multiprocessing import shared_memory
from threading import Thread
import struct
import os
from enum import IntEnum

# REFERENCES
# - On Python side: https://docs.python.org/3/library/multiprocessing.shared_memory.html
# - On C++ side: https://learn.microsoft.com/en-us/windows/win32/memory/creating-named-shared-memory
# - Semaphore docs: https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createsemaphoreexa

# PLANNING NOTES
# - Need handshake protocol, probably need to re-run when glsl / flr reload happens ?
#   - Handshake resolves IDs for UI elems, buffers, images, shaders, task blocks, etc
#   - Initial deserialized UI values ?
#   - Script resolves IDs for each string during handshake, later must use ID only when referencing objects
# - Game loop will probably be a bit more dynamics
#   - Can consist of various "commands" , basically generates a command buffer
#   - Commandbuffer format needs to be documented somewhere (handshake too for that matter)
#   - Sub-allocates into the shared memory
# - On Flr side - need a command buffer interpreter thing
#   - Loops through commands and executes them (already have something like that for executeTaskList)
#   - But here, it will need to include other things like - update UI, upload data, etc
#   - Will still need classic things like barriers, layout transitions, dispatches, run-tasks, etc

# TODO coordinate this with flr, send as commandline or something...
BUF_SIZE = 1<<30

# NOTE Keep in sync with eCmdType in IpcProgram.h
class FlrCmdType(IntEnum):
  CMD_FINISH = 0
  CMD_PUSH_CONSTANTS = 1
  CMD_DISPATCH = 2
  CMD_BARRIER_RW = 3
  CMD_BUFFER_WRITE = 4
  CMD_UNIFORM_WRITE = 5
  CMD_RUN_TASK = 6

# NOTE Keep in sync with eEstablishType in IpcProgram.h
class FlrEstType(IntEnum):
  EST_FINISH = 0
  EST_BUFFER = 1
  EST_UI = 2
  EST_COMPUTE_SHADER = 3
  EST_TASK = 4
  EST_GREET = 0x1F1F1F1F
  EST_FAILED = 0xFFFFFFFF

class FlrHandle:
  def __init__(self, idx : int = 0xFFFFFFFF):
    self.idx = idx
  def isValid(self):
    return self.idx != 0xFFFFFFFF
  
class FlrBufferHandle(FlrHandle):
  pass
  
class FlrComputeShaderHandle(FlrHandle):
  pass

class FlrTaskHandle(FlrHandle):
  pass

def runFlr(exePath, flrPath):
  subprocess.run([exePath, flrPath, "TODO_REMOVE"], stdout=subprocess.PIPE)

class FlrScriptInterface:
  
  # TODO encapsulate members as private ?
  def __init__(self, flrProjPath):
    self.writeDoneSem = win32event.CreateSemaphore(None, 0, 1, "Global_FlrWriteDoneSemaphore")
    self.readDoneSem = win32event.CreateSemaphore(None, 0, 1, "Global_FlrReadDoneSemaphore")
    self.sharedMem = shared_memory.SharedMemory(name="Global_FlrSharedMemory", create=True, size=BUF_SIZE)
    # NOTE - cmd-buffer is allocated from start, all suballocations are made from the end
    self.perFrameOffset = 0
    self.perFrameEnd = BUF_SIZE
    self.perFrameFailure = False

    flrDebugEnable = True
    self.flrExePath = \
        "C:/Users/nithi/Documents/Code/Fluorescence/build/RelWithDebInfo/Fluorescence.exe" \
        if flrDebugEnable else \
        "Fluorescence.exe"
    
    self.flrProjPath = os.path.abspath(flrProjPath)
    self.flrThread = Thread(target = runFlr, args = [self.flrExePath, self.flrProjPath]) 
    self.flrThread.start()

    # TODO remove hardcoded greeting
    self.sharedMem.buf[:5] = b'mssga'

    win32event.ReleaseSemaphore(self.writeDoneSem, 1)
    win32event.WaitForSingleObject(self.readDoneSem, win32event.INFINITE)
    
    self.__resetProject()
    self.__establishProject()
    self.sharedMem.buf[:5] = b'mssgb'

    win32event.ReleaseSemaphore(self.writeDoneSem, 1)
    win32event.WaitForSingleObject(self.readDoneSem, win32event.INFINITE)

  def __del__(self):
    self.flrThread.join()

    win32api.CloseHandle(self.writeDoneSem)
    win32api.CloseHandle(self.readDoneSem)
    
    self.sharedMem.close()
    self.sharedMem.unlink()
  
  def __parseU32(self, offs : int):
    return int.from_bytes(self.sharedMem.buf[offs:offs+4], byteorder='little', signed=False), (offs+4)
  
  def __parseName(self, offs : int):
    for i in range(offs, min(offs + 1000, BUF_SIZE)): 
      if self.sharedMem.buf[i] == 0:
        return str(self.sharedMem.buf[offs:i], 'utf-8'), (i+1)
    return None, offs
  
  def __resetProject(self):
    self.bufferInfos = []
    self.computeShaders = []
    self.taskBlocks = []

  def __establishProject(self):
    greeting, offs = self.__parseU32(0)
    if greeting == FlrEstType.EST_FAILED:
      return False
    assert(greeting == FlrEstType.EST_GREET)
    if greeting != FlrEstType.EST_GREET:
      return False

    while True:
      cmd, offs = self.__parseU32(offs)
      match cmd:
        case FlrEstType.EST_BUFFER:
          bufIdx, offs = self.__parseU32(offs)
          bufCount, offs = self.__parseU32(offs)
          name, offs = self.__parseName(offs)
          assert(bufIdx == len(self.bufferInfos))
          self.bufferInfos.append((bufCount, name))
        case FlrEstType.EST_UI:
          # TODO handle this...
          assert(False) 
        case FlrEstType.EST_COMPUTE_SHADER:
          csidx, offs = self.__parseU32(offs)
          name, offs = self.__parseName(offs)
          assert(csidx == len(self.computeShaders))
          self.computeShaders.append(name)
        case FlrEstType.EST_TASK:
          tidx, offs = self.__parseU32(offs)
          name, offs = self.__parseName(offs)
          assert(tidx == len(self.taskBlocks))
          self.taskBlocks.append(name) 
        case FlrEstType.EST_FINISH:
          return True
        case _:
          return False

  def __resetPerFrameData(self):
    self.perFrameOffset = 0
    self.perFrameEnd = BUF_SIZE
    self.perFrameFailure = False

  def __validateCmdAlloc(self, end : int):
    self.perFrameFailure = self.perFrameFailure or (end > self.perFrameEnd)
    return not self.perFrameFailure

  def __validateDataAlloc(self, start : int):
    self.perFrameFailure = self.perFrameFailure or (start < self.perFrameOffset)
    return not self.perFrameFailure
  
  def getBufferHandle(self, name : str):
    for bufIdx in range(0, len(self.bufferInfos)):
      if name == self.bufferInfos[bufIdx][1]:
        return FlrBufferHandle(bufIdx)
    return FlrBufferHandle()
  
  def __isValidBuffer(self, bufIdx : int, subBufIdx : int):
    if bufIdx < 0 or bufIdx >= len(self.bufferInfos):
      return False
    if subBufIdx != 0xFFFFFFFF and (subBufIdx < 0 or subBufIdx >= self.bufferInfos[bufIdx][0]):
      return False
    return True
  
  def getComputeShaderHandle(self, name : str):
    for csidx in range(0, len(self.computeShaders)):
      if name == self.computeShaders[csidx]:
        return FlrComputeShaderHandle(csidx)
    return FlrComputeShaderHandle()
  
  def getTaskHandle(self, name : str):
    for tidx in range(0, len(self.taskBlocks)):
      if name == self.taskBlocks[tidx]:
        return FlrTaskHandle(tidx)
    return FlrTaskHandle()
  
  def cmdPushConstants(self, push0 : int, push1 : int, push2 : int, push3 : int):
    end = self.perFrameOffset + 4 + 16
    if self.__validateCmdAlloc(end):
      self.sharedMem.buf[self.perFrameOffset:end] = \
          struct.pack("<IIIII", FlrCmdType.CMD_PUSH_CONSTANTS, push0, push1, push2, push3)
      self.perFrameOffset = end

  # TODO special ID types (bufferId, computeShaderId etc)
  def cmdDispatch(self, handle : FlrComputeShaderHandle, groupCountX : int, groupCountY : int, groupCountZ : int):
    assert(handle.isValid())
    end = self.perFrameOffset + 4 + 16
    if self.__validateCmdAlloc(end):
      self.sharedMem.buf[self.perFrameOffset:end] = \
        struct.pack("<IIIII", FlrCmdType.CMD_DISPATCH, handle.idx, groupCountX, groupCountY, groupCountZ)
      self.perFrameOffset = end

  def cmdBarrierRW(self, handle : FlrBufferHandle):
    assert(handle.isValid())
    end = self.perFrameOffset + 4 + 4
    if self.__validateCmdAlloc(end):
      self.sharedMem.buf[self.perFrameOffset:end] = struct.pack("<II", FlrCmdType.CMD_BARRIER_RW, handle.idx)
      self.perFrameOffset = end

  def cmdBufferWrite(self, handle : FlrBufferHandle, subBufIdx : int, dstOffset : int, ba : bytearray):
    assert(handle.isValid())
    bufferId = handle.idx
    assert(self.__isValidBuffer(bufferId, subBufIdx))
    sizeBytes = len(ba)
    end = self.perFrameOffset + 4 + 20
    if self.__validateCmdAlloc(end):
      memStart = self.perFrameEnd - sizeBytes
      if self.__validateDataAlloc(memStart):
        self.sharedMem.buf[self.perFrameOffset:end] = \
          struct.pack("<IIIIII", FlrCmdType.CMD_BUFFER_WRITE, bufferId, subBufIdx, memStart, dstOffset, sizeBytes)
        self.perFrameOffset = end
        # TODO expose a variant where the shared memory data suballocations can be written to directly
        # to avoid this copy
        self.sharedMem.buf[memStart:self.perFrameEnd] = ba[:]
        self.perFrameEnd = memStart

  def cmdUniformWrite(self, dstOffset : int, ba : bytearray):
    sizeBytes = len(ba)
    end = self.perFrameOffset + 4 + 12
    if self.__validateCmdAlloc(end):
      memStart = self.perFrameEnd - sizeBytes
      if self.__validateDataAlloc(memStart):
        self.sharedMem.buf[self.perFrameOffset:end] = struct.pack("<IIII", FlrCmdType.CMD_UNIFORM_WRITE, memStart, dstOffset, sizeBytes)
        self.perFrameOffset = end
        # TODO expose a variant where the shared memory data suballocations can be written to directly
        # to avoid this copy
        self.sharedMem.buf[memStart:self.perFrameEnd] = ba[:]
        self.perFrameEnd = memStart

  def cmdRunTask(self, handle : FlrTaskHandle):
    assert(handle.isValid())
    end = self.perFrameOffset + 4 + 4
    if self.__validateCmdAlloc(end):
      self.sharedMem.buf[self.perFrameOffset:end] = struct.pack("<II", FlrCmdType.CMD_RUN_TASK, handle.idx)
      self.perFrameOffset = end

  def __cmdFinalize(self):
    end = self.perFrameOffset + 4
    if self.__validateCmdAlloc(end):
      self.sharedMem.buf[self.perFrameOffset:end] = struct.pack("<I", FlrCmdType.CMD_FINISH)
      self.perFrameOffset = end
  
  def tick(self):
    self.__cmdFinalize()
    win32event.ReleaseSemaphore(self.writeDoneSem, 1)
    # wait for read to complete - handling flr app termination if needed
    break_outer = False
    while True:
      res = win32event.WaitForSingleObject(self.readDoneSem, 500)
      if res == win32event.WAIT_OBJECT_0:
        break 
      elif not self.flrThread.is_alive():
        break_outer = True
        break
    self.__resetPerFrameData()
    return not break_outer