
import flrlib
import struct
import pbd
import pid
import numpy as np
import math

gizmoViewStart = 0
gizmoViewEnd = 0

motorInputs = []
body = None
def initScene():
  pbd.resetScene()

  global motorInputs
  global body

  motorInputs = []

  body = pbd.createBox([0, 0, 0], [2.0, 0.25, 2.0])
  body.addNewNode([0.0, 2.0, 0.0])
  motorPositions = [
      [-3.5, 0.0, -3.5],
      [-3.5, 0.0, 3.5],
      [3.5, 0.0, 3.5],
      [3.5, 0.0, -3.5]]
  for i in range(4):
    motorPosition = motorPositions[i]
    motor = pbd.createBox(motorPosition, [0.5, 0.45, 0.5])
    mountNodeMidIdx = pbd.createNode(motorPosition)
    mountNodeTopIdx = pbd.createNode(motorPosition + np.array([0.0, 1.0, 0.0]))
    mountNodeRightIdx = pbd.createNode(motorPosition + np.array([1.0, 0.0, 0.0]))
    mountNodeLeftIdx = pbd.createNode(motorPosition + np.array([-1.0, 0.0, 0.0]))
    body.addNode(mountNodeMidIdx) 
    body.addNode(mountNodeTopIdx)
    body.addNode(mountNodeRightIdx)
    body.addNode(mountNodeLeftIdx)
    motor.addNode(mountNodeMidIdx)
    motor.addNode(mountNodeTopIdx)
    motor.addNode(mountNodeRightIdx)
    motor.addNode(mountNodeLeftIdx)
    motorInputs.append(
      pbd.createMotor(
        mountNodeMidIdx, mountNodeTopIdx, mountNodeLeftIdx, mountNodeRightIdx, 1000.0, (i%2) == 0))
  
  pbd.finalizeScene()

  pid.reset()

def printSensorLogs():
  sensorPos = body.centerOfMass
  sensorRot = body.rotation
  print(f"POS: ({sensorPos[0]}, {sensorPos[1]}, {sensorPos[2]})")
  print(f"ROT: ({sensorRot[0][0]}, {sensorRot[0][1]}, {sensorRot[0][2]},")
  print(f"      {sensorRot[1][0]}, {sensorRot[1][1]}, {sensorRot[1][2]},")
  print(f"      {sensorRot[2][0]}, {sensorRot[2][1]}, {sensorRot[2][2]})")

# TODO make sure vert count cannot change during scene 
# alternatively handle vert count changes too
initScene()

params = flrlib.FlrParams()
params.append("VERT_COUNT", pbd.nodeCount)
# TODO float params...
# params.append("FLOOR_HEIGHT", pbd.floorHeight)
flr = flrlib.FlrScriptInterface("FlrProject/Sandbox.flr", params, flrDebugEnable = False)

# buffer handles
positionsHandle = flr.getBufferHandle("positions")
gizmoViewHandle = flr.getBufferHandle("gizmoView")
gizmoBufferHandle = flr.getBufferHandle("gizmoBuffer")

pbd.floorHeight = flr.getConstFloat("FLOOR_HEIGHT")
maxGizmoCount = flr.getConstUint("MAX_GIZMOS")

# ui handles
simulateCheckbox = flr.getCheckboxHandle("ENABLE_SIM")
enableFlightController = flr.getCheckboxHandle("USE_CONTROLLER")
testMotorsCheckbox = flr.getCheckboxHandle("OSCILLATE_MOTORS")
logFrequency = flr.getSliderUintHandle("LOG_FREQUENCY")
trailFrequency = flr.getSliderUintHandle("TRAIL_FREQUENCY")
throttle0 = flr.getSliderFloatHandle("THROTTLE0")
throttle1 = flr.getSliderFloatHandle("THROTTLE1")
throttle2 = flr.getSliderFloatHandle("THROTTLE2")
throttle3 = flr.getSliderFloatHandle("THROTTLE3")

pid_linProp = flr.getSliderFloatHandle("LIN_PROP")
pid_linDiff = flr.getSliderFloatHandle("LIN_DIFF")
pid_linInt = flr.getSliderFloatHandle("LIN_INT")

def uploadPositions():
  buf = bytearray(pbd.nodeCount * 4 * 3)
  for i in range(pbd.nodeCount):
    buf[12*i:12*(i+1)] = struct.pack(
        "<fff", pbd.nodePositions[i][0], pbd.nodePositions[i][1], pbd.nodePositions[i][2])
  flr.cmdBufferWrite(positionsHandle, 0xFFFFFFFF, 0, buf)

def addGizmo(tr, rot):
  global gizmoViewEnd
  buf = bytearray(64)
  buf[0:16] = struct.pack("<ffff", rot[0][0], rot[1][0], rot[2][0], 0.0)
  buf[16:32] = struct.pack("<ffff", rot[0][1], rot[1][1], rot[2][1], 0.0)
  buf[32:48] = struct.pack("<ffff", rot[0][2], rot[1][2], rot[2][2], 0.0)
  buf[48:64] = struct.pack("<ffff", tr[0], tr[1], tr[2], 1.0)
  offs = gizmoViewEnd % maxGizmoCount
  flr.cmdBufferWrite(gizmoBufferHandle, 0, offs * 64, buf)
  gizmoViewEnd += 1

def updateGizmos():
  global gizmoViewStart
  buf = bytearray(8)
  buf[:] = struct.pack("<II", gizmoViewStart, gizmoViewEnd)
  flr.cmdBufferWrite(gizmoViewHandle, 0xFFFFFFFF, 0, buf)
  usedCount = gizmoViewEnd - gizmoViewStart
  if usedCount == maxGizmoCount:
    gizmoViewStart += 1

frame = 0
while True:  
  if flr.getCheckbox(enableFlightController):
    pid.kProp = flr.getSliderFloat(pid_linProp)
    pid.kDiff = flr.getSliderFloat(pid_linDiff)
    pid.kInt = flr.getSliderFloat(pid_linInt)
    throttleSolution = pid.update(body.centerOfMass, body.rotation, pbd.DT)
    for i in range(4):
      motorInputs[i].setThrottle(throttleSolution[i])
  elif flr.getCheckbox(testMotorsCheckbox):
    pid.reset()
    motorInputs[0].setThrottle(0.1 + 0.1 * math.sin(pbd.time))
    motorInputs[1].setThrottle(0.1 + 0.1 * math.sin(1.3 * pbd.time + 2))
    motorInputs[2].setThrottle(0.1 + 0.1 * math.sin(2.12 * pbd.time + 1))
    motorInputs[3].setThrottle(0.1 + 0.1 * math.sin(0.9 * pbd.time + 3.1))
  else:
    pid.reset()
    motorInputs[0].setThrottle(flr.getSliderFloat(throttle0))
    motorInputs[1].setThrottle(flr.getSliderFloat(throttle1))
    motorInputs[2].setThrottle(flr.getSliderFloat(throttle2))
    motorInputs[3].setThrottle(flr.getSliderFloat(throttle3))

  logFreqSecs = flr.getSliderUint(logFrequency)
  if logFreqSecs > 0 and frame%(30 * logFreqSecs) == 0:
    printSensorLogs()
  
  trailFreq = flr.getSliderUint(trailFrequency)
  if trailFreq == 0:
    gizmoViewStart = gizmoViewEnd
  elif frame%(3*trailFreq) == 0:
    addGizmo(body.centerOfMass, body.rotation)
  
  if flr.getCheckbox(simulateCheckbox):
    pbd.stepSimulation()

  uploadPositions()
  updateGizmos()
  match flr.tick():
    case flrlib.FlrTickResult.TR_REINIT:
      initScene()
    case flrlib.FlrTickResult.TR_TERMINATE:
      break
  frame += 1

exit(0) 