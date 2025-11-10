
import flrlib
import struct
import math

flr = flrlib.FlrScriptInterface("FlrProject/Test.flr")

bufHandle = flr.getBufferHandle("testBuf")

t = 0.0
DT = 1.0/30.0
while True:
  t += DT
  f = 0.5 * math.sin(2.0 * t) + 0.5
  flr.cmdBufferWrite(bufHandle, 0xFFFFFFFF, 0, struct.pack("<fff", f, 0.5 * f, f))

  if not flr.tick():
    break

exit(0) 