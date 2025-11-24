
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

# Fluorescence IPC protocol
# - The protocol consists of a synchronized series of communications in a shared memory buffer
# - flr messages are host app --> client script communications
#   - messages are used during project init for transmitting resources and name strings
#   - messages are also used after each tick, to communicate UI updates
# - flr cmds are client script --> host app communications
#   - cmds are used upon app launch to set compile-time parameters for the flr project
#   - cmds are used during each tick to interact with the flr api, update buffers, run dispatches, run tasks, etc
# - Script implementations of the protocol need to implement the following:
#   - Create the sync objects and shared memory, launch the Fluorescence app with the -ipc arg
#   - flr cmd buffer assembly and flr message parsing into/from shared memory
#   - Handshake with flr app: 
#     - Assemble cmds to generate compile-time params into shared memory before flr app launch
#     - Wait for app to finish processing the cmds and to write out the initial project establishment packet
#     - Parse all the names and resources from the project establishment
#   - Tick implementation:
#     - Assemble cmds based on user script calls into the lib
#     - Wait for app to finish processing tick cmds, wait for the app to write out an update packet
#     - Consume the update packet, update any changed state, terminate or re-initialize as needed
#       - Timeout if flr app exits

# TODO - finish documenting python library-specific details
# Fluorescence in Python
# - flrlib is a python implementation of the above IPC protocol
# - It is designed for fast prototyping and workflow integration of Fluorescence with other tools or DCCs

# TODO LIST
# - Minimize required user-side handling of project re-init, specifically avoid having to regenerate handles
#   - Handle registry, with internal references to handle objects?
#   - Could repair all previously issued handles...

# TODO coordinate this with flr, send as commandline or something...
BUF_SIZE = 1<<30

# NOTE Keep in sync with eCmdType in IpcProgram.h
class FlrCmdType(IntEnum):
  CMD_FINISH = 0
  CMD_UINT_PARAM = 1
  CMD_PUSH_CONSTANTS = 2
  CMD_DISPATCH = 3
  CMD_BARRIER_RW = 4
  CMD_BUFFER_WRITE = 5
  CMD_BUFFER_STAGED_UPLOAD = 6
  CMD_UNIFORM_WRITE = 7
  CMD_RUN_TASK = 8

# NOTE Keep in sync with eMessageType in IpcProgram.h
class FlrMessageType(IntEnum):
  FMT_FINISH = 0
  FMT_BUFFER = 1
  FMT_UI = 2
  FMT_UI_UPDATE = 3
  FMT_COMPUTE_SHADER = 4
  FMT_TASK = 5
  FMT_CONST = 6
  FMT_REINIT = 7
  FMT_GREET = 0x1F1F1F1F
  FMT_FAILED = 0xFFFFFFFF

class FlrTickResult(IntEnum):
  TR_SUCCESS = 0
  TR_TERMINATE = 1
  TR_REINIT = 2

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

class FlrUintSliderHandle(FlrHandle):
  pass
  
class FlrIntSliderHandle(FlrHandle):
  pass

class FlrFloatSliderHandle(FlrHandle):
  pass

class FlrCheckboxHandle(FlrHandle):
  pass

def runFlr(exePath, flrPath):
  subprocess.run([exePath, flrPath, "-ipc"], stdout=subprocess.PIPE)

class FlrBufInfo:
  def __init__(self, name : str, bufferIdx : int, bufferSize : int, bufferCount : int, bCpuAccess : bool):
    self.name = name
    self.bufferIdx = bufferIdx
    self.bufferSize = bufferSize
    self.bufferCount = bufferCount
    self.bCpuAccess = bCpuAccess

class FlrParams:
  def __init__(self):
    self.names = []
    self.values = []
  
  def append(self, name : str, value : int):
    self.names.append(name)
    self.values.append(value)

class FlrUiElem:
  def __init__(self, name : str, offset : int):
    self.name = name
    self.offset = offset

class FlrScriptInterface:
  # TODO encapsulate members as private ?
  def __init__(self, flrProjPath, params : FlrParams, flrDebugEnable = False):
    self.writeDoneSem = win32event.CreateSemaphore(None, 0, 1, "Global_FlrWriteDoneSemaphore")
    self.readDoneSem = win32event.CreateSemaphore(None, 0, 1, "Global_FlrReadDoneSemaphore")
    self.sharedMem = shared_memory.SharedMemory(name="Global_FlrSharedMemory", create=True, size=BUF_SIZE)
    # NOTE - cmd-buffer is allocated from start, all suballocations are made from the end
    self.perFrameOffset = 0
    self.perFrameEnd = BUF_SIZE
    self.perFrameFailure = False

    self.flrExePath = \
        "C:/Users/nithi/Documents/Code/Fluorescence/build/RelWithDebInfo/Fluorescence.exe" \
        if flrDebugEnable else \
        "Fluorescence.exe"
    
    for i in range(len(params.names)):
      self.__cmdUintParam(params.names[i], params.values[i])
    self.__cmdFinalize()
    self.__resetPerFrameData()
    
    self.flrProjPath = os.path.abspath(flrProjPath)
    self.flrThread = Thread(target = runFlr, args = [self.flrExePath, self.flrProjPath]) 
    self.flrThread.start()

    # NOTE waiting for params to be read and initial establishment packet to be written
    win32event.WaitForSingleObject(self.readDoneSem, win32event.INFINITE)
    
    self.__resetProject()
    self.__processPacket()
    self.bReinitProject = False
    
    # NOTE next signal is not set until after the initial draw's cmdlist is finished

  def __del__(self):
    self.flrThread.join()

    win32api.CloseHandle(self.writeDoneSem)
    win32api.CloseHandle(self.readDoneSem)
    
    self.sharedMem.close()
    self.sharedMem.unlink()
  
  def __parseU32(self, offs : int):
    return int.from_bytes(self.sharedMem.buf[offs:offs+4], byteorder='little', signed=False), (offs+4)
  
  def __parseI32(self, offs : int):
    return int.from_bytes(self.sharedMem.buf[offs:offs+4], byteorder='little', signed=True), (offs+4)
  
  def __parseF32(self, offs : int):
    return struct.unpack("<f", self.sharedMem.buf[offs:offs+4]), (offs+4)
  
  def __parseChar(self, offs : int):
    return str(self.sharedMem.buf[offs:offs+1], 'utf-8'), (offs+1)
  
  def __parseName(self, offs : int):
    for i in range(offs, min(offs + 1000, BUF_SIZE)): 
      if self.sharedMem.buf[i] == 0:
        return str(self.sharedMem.buf[offs:i], 'utf-8'), (i+1)
    return None, offs
  
  def __resetProject(self):
    self.bufferInfos = []
    self.computeShaders = []
    self.taskBlocks = []
    self.constUints = []
    self.constInts = []
    self.constFloats = []
    self.uiBuffer = []
    self.uintSliders = []
    self.intSliders = []
    self.floatSliders = []
    self.checkboxes = []
    self.bReinitProject = False

  def __processMessage(self, cmd : int, offs : int):
    match cmd:

      case FlrMessageType.FMT_BUFFER:
        bufIdx, offs = self.__parseU32(offs)
        bufSize, offs = self.__parseU32(offs)
        bufCount, offs = self.__parseU32(offs)
        bufType, offs = self.__parseU32(offs)
        name, offs = self.__parseName(offs)
        assert(bufIdx == len(self.bufferInfos))
        self.bufferInfos.append(FlrBufInfo(name, bufIdx, bufSize, bufCount, bufType == 1))

      case FlrMessageType.FMT_UI:
        uiType, offs = self.__parseU32(offs)
        assert(uiType < 5)
        if uiType == 0:
          # buffer size
          uiBufSize, offs = self.__parseU32(offs)
          self.uiBuffer = bytearray(uiBufSize)
        else:
          uiBufOffset, offs = self.__parseU32(offs)
          name, offs = self.__parseName(offs)
          # TODO formalize these sub-ui types
          if uiType == 1:
            # uint slider
            self.uintSliders.append(FlrUiElem(name, uiBufOffset))
          elif uiType == 2:
            # int slider
            self.uintSliders.append(FlrUiElem(name, uiBufOffset))
          elif uiType == 3:
            # float slider
            self.floatSliders.append(FlrUiElem(name, uiBufOffset))
          elif uiType == 4:
            # checkbox
            self.checkboxes.append(FlrUiElem(name, uiBufOffset))

      case FlrMessageType.FMT_UI_UPDATE:
        allocOffs, offs = self.__parseU32(offs)
        allocSize, offs = self.__parseU32(offs)
        assert(allocSize == len(self.uiBuffer))
        self.uiBuffer[:] = self.sharedMem.buf[allocOffs:allocOffs+allocSize]
      
      case FlrMessageType.FMT_COMPUTE_SHADER:
        csidx, offs = self.__parseU32(offs)
        name, offs = self.__parseName(offs)
        assert(csidx == len(self.computeShaders))
        self.computeShaders.append(name)

      case FlrMessageType.FMT_TASK:
        tidx, offs = self.__parseU32(offs)
        name, offs = self.__parseName(offs)
        assert(tidx == len(self.taskBlocks))
        self.taskBlocks.append(name) 

      case FlrMessageType.FMT_CONST:
        c, offs = self.__parseChar(offs)
        if c == 'i':
          i, offs = self.__parseI32(offs)
          name, offs = self.__parseName(offs)
          self.constInts.append((name, i))
        elif c == 'I':
          u, offs = self.__parseU32(offs)
          name, offs = self.__parseName(offs)
          self.constUints.append((name, u))
        elif c == 'f':
          f, offs = self.__parseF32(offs)
          name, offs = self.__parseName(offs)
          self.constFloats.append((name, f))
        else:
          assert(False)

      case FlrMessageType.FMT_REINIT:
        self.__resetProject()
        self.bReinitProject = True
      
      case _:
        return False, offs
    return True, offs

  def __processPacket(self):
    greeting, offs = self.__parseU32(0)
    if greeting == FlrMessageType.FMT_FAILED:
      return False
    assert(greeting == FlrMessageType.FMT_GREET)
    if greeting != FlrMessageType.FMT_GREET:
      return False
    
    while True:
      cmd, offs = self.__parseU32(offs)
      if cmd == FlrMessageType.FMT_FINISH:
        return True
      bResult, offs = self.__processMessage(cmd, offs)
      if not bResult:
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
      if name == self.bufferInfos[bufIdx].name:
        return FlrBufferHandle(bufIdx)
    return FlrBufferHandle()
  
  def __isValidBuffer(self, bufIdx : int, subBufIdx : int):
    if bufIdx < 0 or bufIdx >= len(self.bufferInfos):
      return False
    if subBufIdx != 0xFFFFFFFF and (subBufIdx < 0 or subBufIdx >= self.bufferInfos[bufIdx].bufferCount):
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
  
  def __getUiHandle(self, name : str, arr):
    for i in range(0, len(arr)):
      if name == arr[i].name:
        return i
    return 0xFFFFFFFF
  
  def getSliderFloatHandle(self, name : str) -> FlrFloatSliderHandle:
    return FlrFloatSliderHandle(self.__getUiHandle(name, self.floatSliders))
  def getSliderUintHandle(self, name : str) -> FlrUintSliderHandle:
    return FlrUintSliderHandle(self.__getUiHandle(name, self.uintSliders))
  def getSliderIntHandle(self, name : str) -> FlrIntSliderHandle:
    return FlrIntSliderHandle(self.__getUiHandle(name, self.intSliders))
  def getCheckboxHandle(self, name : str) -> FlrCheckboxHandle:
    return FlrCheckboxHandle(self.__getUiHandle(name, self.checkboxes))
  
  def getSliderFloat(self, handle : FlrFloatSliderHandle) -> float:
    offs = self.floatSliders[handle.idx].offset
    return struct.unpack("<f", self.uiBuffer[offs:offs+4])
  
  def getSliderUint(self, handle : FlrUintSliderHandle) -> int:
    offs = self.uintSliders[handle.idx].offset
    return int.from_bytes(self.uiBuffer[offs:offs+4], byteorder='little', signed=False)
    
  def getSliderInt(self, handle : FlrIntSliderHandle) -> int:
    offs = self.intSliders[handle.idx].offset
    return int.from_bytes(self.uiBuffer[offs:offs+4], byteorder='little', signed=True)
    
  def getCheckbox(self, handle : FlrCheckboxHandle) -> int:
    offs = self.checkboxes[handle.idx].offset
    return int.from_bytes(self.uiBuffer[offs:offs+4], byteorder='little', signed=False)
  
  def getConstFloat(self, name : str) -> float:
    for c in self.constFloats:
      if name == c[0]:
        return c[1]
    assert(False)
    return 0.0
  
  def getConstInt(self, name : str) -> int:
    for c in self.constInts:
      if name == c[0]:
        return c[1]
    assert(False)
    return 0

  def getConstUint(self, name : str) -> int:
    for c in self.constUints:
      if name == c[0]:
        return c[1]
    assert(False)
    return 0
  
  def cmdPushConstants(self, push0 : int, push1 : int, push2 : int, push3 : int):
    end = self.perFrameOffset + 4 + 16
    if self.__validateCmdAlloc(end):
      self.sharedMem.buf[self.perFrameOffset:end] = \
          struct.pack("<IIIII", FlrCmdType.CMD_PUSH_CONSTANTS, push0, push1, push2, push3)
      self.perFrameOffset = end

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
    bufInfo = self.bufferInfos[bufferId]
    assert(bufInfo.bCpuAccess)
    sizeBytes = len(ba)
    assert(dstOffset >= 0 and (dstOffset + sizeBytes) <= bufInfo.bufferSize)
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

  def cmdBufferStagedUpload(self, handle : FlrBufferHandle, subBufIdx : int, ba : bytearray):
    assert(handle.isValid())
    bufferId = handle.idx
    assert(self.__isValidBuffer(bufferId, subBufIdx))
    bufInfo = self.bufferInfos[bufferId]
    sizeBytes = len(ba)
    assert(sizeBytes == bufInfo.bufferSize)
    end = self.perFrameOffset + 4 + 16
    if self.__validateCmdAlloc(end):
      memStart = self.perFrameEnd - sizeBytes
      if self.__validateDataAlloc(memStart):
        self.sharedMem.buf[self.perFrameOffset:end] = \
          struct.pack("<IIIII", FlrCmdType.CMD_BUFFER_STAGED_UPLOAD, bufferId, subBufIdx, memStart, sizeBytes)
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

  def __cmdUintParam(self, name : str, value : int):
    ba = name.encode('utf-8')
    nameLen = len(ba)
    end = self.perFrameOffset + 4 + 12
    if self.__validateCmdAlloc(end):
      memStart = self.perFrameEnd - nameLen
      if self.__validateDataAlloc(memStart):
        self.sharedMem.buf[self.perFrameOffset:end] = struct.pack("<IIII", FlrCmdType.CMD_UINT_PARAM, memStart, nameLen, value)
        self.perFrameOffset = end
        self.sharedMem.buf[memStart:memStart+nameLen] = ba
        self.perFrameEnd = memStart

  def __cmdFinalize(self):
    end = self.perFrameOffset + 4
    if self.__validateCmdAlloc(end):
      self.sharedMem.buf[self.perFrameOffset:end] = struct.pack("<I", FlrCmdType.CMD_FINISH)
      self.perFrameOffset = end
  
  def tick(self) -> FlrTickResult:
    self.__cmdFinalize()
    self.__resetPerFrameData()
    win32event.ReleaseSemaphore(self.writeDoneSem, 1)
    # NOTE wait for cmdlist read to complete and any update packet to be written
    # uses timout to handle flr app termination
    while True:
      res = win32event.WaitForSingleObject(self.readDoneSem, 500)
      if res == win32event.WAIT_OBJECT_0:
        if not self.__processPacket():
          return FlrTickResult.TR_TERMINATE
        if self.bReinitProject:
          self.bReinitProject = False
          return FlrTickResult.TR_REINIT
        return FlrTickResult.TR_SUCCESS
      elif not self.flrThread.is_alive():
        return FlrTickResult.TR_TERMINATE