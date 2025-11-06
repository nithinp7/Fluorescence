
import subprocess
import win32event
import win32api
from multiprocessing import shared_memory
from threading import Thread
import math
import struct
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

# TODO coordinate this with flr, send as commandlineor something...
BUF_SIZE = 1<<30

def runFlr(exePath, flrPath):
  subprocess.run([exePath, flrPath, "TODO_REMOVE"], stdout=subprocess.PIPE)


# TODO handshake helpers, initialize buffer IDs, find elems by string, etc...
  
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
    # TODO convert from local to abs path before sending to flr
    self.flrExePath = \
        "C:/Users/nithi/Documents/Code/Fluorescence/build/RelWithDebInfo/Fluorescence.exe" \
        if flrDebugEnable else \
        "Fluorescence.exe"

    self.flrProjPath = flrProjPath
    self.flrThread = Thread(target = runFlr, args = [self.flrExePath, self.flrProjPath]) 
    self.flrThread.start()

    self.sharedMem.buf[:5] = b'mssga'

    win32event.ReleaseSemaphore(self.writeDoneSem, 1)
    win32event.WaitForSingleObject(self.readDoneSem, win32event.INFINITE)

    self.sharedMem.buf[:5] = b'mssgb'

    win32event.ReleaseSemaphore(self.writeDoneSem, 1)
    win32event.WaitForSingleObject(self.readDoneSem, win32event.INFINITE)

  def __del__(self):
    self.flrThread.join()

    win32api.CloseHandle(self.writeDoneSem)
    win32api.CloseHandle(self.readDoneSem)
    
    self.sharedMem.close()
    self.sharedMem.unlink()

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

  def cmdPushConstants(self, push0 : int, push1 : int, push2 : int, push3 : int):
    end = self.perFrameOffset + 4 + 16
    if self.__validateCmdAlloc(end):
      self.sharedMem.buf[self.perFrameOffset:end] = struct.pack("<IIIII", 1, push0, push1, push2, push3)
      self.perFrameOffset = end

  # TODO special ID types (bufferId, computeShaderId etc)
  def cmdDispatch(self, computeShaderId : int, groupCountX : int, groupCountY : int, groupCountZ : int):
    end = self.perFrameOffset + 4 + 16
    if self.__validateCmdAlloc(end):
      self.sharedMem.buf[self.perFrameOffset:end] = \
        struct.pack("<IIIII", 2, computeShaderId, groupCountX, groupCountY, groupCountZ)
      self.perFrameOffset = end

  def cmdBarrierRW(self, bufferId : int):
    end = self.perFrameOffset + 4 + 4
    if self.__validateCmdAlloc(end):
      self.sharedMem.buf[self.perFrameOffset:end] = struct.pack("<II", 3, bufferId)
      self.perFrameOffset = end

  def cmdBufferWrite(self, bufferId : int, subBufIdx : int, dstOffset : int, ba : bytearray):
    sizeBytes = len(ba)
    end = self.perFrameOffset + 4 + 20
    if self.__validateCmdAlloc(end):
      memStart = self.perFrameEnd - sizeBytes
      if self.__validateDataAlloc(memStart):
        self.sharedMem.buf[self.perFrameOffset:end] = \
          struct.pack("<IIIIII", 4, bufferId, subBufIdx, memStart, dstOffset, sizeBytes)
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
        self.sharedMem.buf[self.perFrameOffset:end] = struct.pack("<IIII", 5, memStart, dstOffset, sizeBytes)
        self.perFrameOffset = end
        # TODO expose a variant where the shared memory data suballocations can be written to directly
        # to avoid this copy
        self.sharedMem.buf[memStart:self.perFrameEnd] = ba[:]
        self.perFrameEnd = memStart

  def cmdRunTask(self, taskId : int):
    end = self.perFrameOffset + 4 + 4
    if self.__validateCmdAlloc(end):
      self.sharedMem.buf[self.perFrameOffset:end] = struct.pack("<II", 6, taskId)
      self.perFrameOffset = end

  def __cmdFinalize(self):
    end = self.perFrameOffset + 4
    if self.__validateCmdAlloc(end):
      self.sharedMem.buf[self.perFrameOffset:end] = struct.pack("<I", 0)
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

# TODO move this to a separate file, once the above can be turned into a package...
# TEST USAGE - 
    # "C:/Users/nithi/Documents/Code/Fluorescence/ScriptLib/Python_WIP/FlrProject/Test.flr"

flr = FlrScriptInterface("C:/Users/nithi/Documents/Code/Fluorescence/ScriptLib/Python_WIP/FlrProject/Test.flr")

t = 0.0
DT = 1.0/30.0
while True:
  # TODO per-frame writing...
  t += DT
  f = 0.5 * math.sin(2.0 * t) + 0.5
  flr.cmdBufferWrite(0, 0xFFFFFFFF, 0, struct.pack("<fff", f, 0.5 * f, f))

  if not flr.tick():
    break

exit(0) 