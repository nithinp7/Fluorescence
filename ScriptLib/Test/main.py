
import flrlib

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