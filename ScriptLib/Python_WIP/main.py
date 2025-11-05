
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
writeDoneSem = win32event.CreateSemaphore(None, 0, 1, "Global_FlrWriteDoneSemaphore")
readDoneSem = win32event.CreateSemaphore(None, 0, 1, "Global_FlrReadDoneSemaphore")
sharedMem = shared_memory.SharedMemory(name="Global_FlrSharedMemory", create=True, size=BUF_SIZE)

def runFlr():
  # TODO convert from local to abs path before sending to flr
  subprocess.run( \
      ["Fluorescence.exe", \
       "C:/Users/nithi/Documents/Code/TestScripts/WindowsIPC/FlrProject/Test.flr", \
      "placeholder"], \
      stdout=subprocess.PIPE,)
      #  "C:/Users/nithi/Documents/Code/TestScripts/WindowsIPC/FlrProject/Test.flr" \
  
      #"C:/Users/nithi/Documents/Code/Fluorescence/Projects/CornellBox/CornellBox.flr", \

thread = Thread(target = runFlr)
thread.start()

sharedMem.buf[:5] = b'mssga'

win32event.ReleaseSemaphore(writeDoneSem, 1)
win32event.WaitForSingleObject(readDoneSem, win32event.INFINITE)

sharedMem.buf[:5] = b'mssgb'

win32event.ReleaseSemaphore(writeDoneSem, 1)
win32event.WaitForSingleObject(readDoneSem, win32event.INFINITE)

# TODO handshake helpers, initialize buffer IDs, find elems by string, etc...

# TODO encapsulate these helpers into a class
# NOTE - cmd-buffer is allocated from start, all suballocations are made from the end
perFrameOffset = 0
perFrameEnd = BUF_SIZE
perFrameFailure = False

def resetPerFrameData():
  global perFrameOffset
  global perFrameEnd
  global perFrameFailure
  perFrameOffset = 0
  perFrameOffset = BUF_SIZE
  perFrameFailure = False

def validateCmdAlloc(end : int):
  global perFrameFailure
  perFrameFailure = perFrameFailure or (end > perFrameEnd)
  return not perFrameFailure

def validateDataAlloc(start : int):
  global perFrameFailure
  perFrameFailure = perFrameFailure or (start < perFrameOffset)

def cmdPushConstants(push0 : int, push1 : int, push2 : int, push3 : int):
  global perFrameOffset
  end = perFrameOffset + 4 + 16
  if validateCmdAlloc(end):
    sharedMem.buf[perFrameOffset:end] = struct.pack("<IIIII", 1, push0, push1, push2, push3)
    perFrameOffset = end

# TODO special ID types (bufferId, computeShaderId etc)
def cmdDispatch(computeShaderId : int, groupCountX : int, groupCountY : int, groupCountZ : int):
  global perFrameOffset
  end = perFrameOffset + 4 + 16
  if validateCmdAlloc(end):
    sharedMem.buf[perFrameOffset:end] = \
      struct.pack("<IIIII", 1, computeShaderId, groupCountX, groupCountY, groupCountZ)
    perFrameOffset = end

def cmdBarrierRW(bufferId : int):
  global perFrameOffset
  end = perFrameOffset + 4 + 4
  if validateCmdAlloc(end):
    sharedMem.buf[perFrameOffset:end] = struct.pack("<II", 2, bufferId)
    perFrameOffset = end

def cmdBufferWrite(bufferId : int, subBufIdx : int, dstOffset : int, ba : bytearray):
  sizeBytes = len(ba)
  global perFrameOffset
  global perFrameEnd
  end = perFrameOffset + 4 + 24
  if validateCmdAlloc(end):
    memStart = perFrameEnd - sizeBytes
    if validateDataAlloc(memStart):
      sharedMem.buf[perFrameOffset:end] = \
        struct.pack("<IIIII", 3, bufferId, subBufIdx, memStart, dstOffset, sizeBytes)
      perFrameOffset = end
      # TODO expose a variant where the shared memory data suballocations can be written to directly
      # to avoid this copy
      sharedMem.buf[memStart:perFrameEnd] = ba[:]
      perFrameEnd = memStart

def cmdUniformWrite(dstOffset : int, ba : bytearray):
  sizeBytes = len(ba)
  global perFrameOffset
  global perFrameEnd
  end = perFrameOffset + 4 + 12
  if validateCmdAlloc(end):
    memStart = perFrameEnd - sizeBytes
    if validateDataAlloc(memStart):
      sharedMem.buf[perFrameOffset:end] = struct.pack("<IIII", 4, memStart, dstOffset, sizeBytes)
      perFrameOffset = end
      # TODO expose a variant where the shared memory data suballocations can be written to directly
      # to avoid this copy
      sharedMem.buf[memStart:perFrameEnd] = ba[:]
      perFrameEnd = memStart

t = 0.0
DT = 1.0/30.0
while True:
  # TODO per-frame writing...
  t += DT
  f = 0.5 * math.sin(2.0 * t) + 0.5
  #0xFFFFFFFF
  sharedMem.buf[0:28] = struct.pack("<IIIIIII", 4, 0, 0xFFFFFFFF, 28, 0, 12, 0)
  sharedMem.buf[28:40] = struct.pack("<fff", f, f, f)

  win32event.ReleaseSemaphore(writeDoneSem, 1)
  # wait for read to complete - handling flr app termination if needed
  break_outer = False
  while True:
    res = win32event.WaitForSingleObject(readDoneSem, 500)
    if res == win32event.WAIT_OBJECT_0:
      break
    elif not thread.is_alive():
      break_outer = True
      break
  if break_outer:
    break

thread.join()

win32api.CloseHandle(writeDoneSem)
win32api.CloseHandle(readDoneSem)

sharedMem.close()
sharedMem.unlink()

exit(0) 