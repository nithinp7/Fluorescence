
import flrlib
import struct
import pbd
import pid
import numpy as np
import math
import random

gizmoViewStart = 0
gizmoViewEnd = 0

motorInputs = [None, None, None, None]
motorShapes = [None, None, None, None]

body = None
def initScene():
  pbd.resetScene()

  global body

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
    motorShapes[i] = motor
    motorInputs[i] = pbd.createMotor(
        mountNodeMidIdx, mountNodeTopIdx, mountNodeLeftIdx, mountNodeRightIdx, 1000.0, (i%2) == 0)
    # motorInputs[i] = pbd.createRotor(motor, mountNodeTopIdx, np.array([0.0, 1.0, 0.0]), 500.0, (i%2) == 0)
  
  pbd.finalizeScene()

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
wayPointsHandle = flr.getBufferHandle("wayPointPositions")
nodeMaterialsHandle = flr.getBufferHandle("nodeMaterials")
throttlesBufferHandle = flr.getBufferHandle("throttleData")
gizmoViewHandle = flr.getBufferHandle("gizmoView")
gizmoBufferHandle = flr.getBufferHandle("gizmoBuffer")

pbd.floorHeight = flr.getConstFloat("FLOOR_HEIGHT")
maxGizmoCount = flr.getConstUint("MAX_GIZMOS")
wayPointCount = flr.getConstUint("WAYPOINT_COUNT")

# ui handles
simulateCheckbox = flr.getCheckboxHandle("ENABLE_SIM")
enableFlightController = flr.getCheckboxHandle("USE_CONTROLLER")
pinToOrigin = flr.getCheckboxHandle("PIN_TO_ORIGIN")
disableFloor = flr.getCheckboxHandle("DISABLE_FLOOR")
testMotorsCheckbox = flr.getCheckboxHandle("OSCILLATE_MOTORS")
logFrequency = flr.getSliderUintHandle("LOG_FREQUENCY")
trailFrequency = flr.getSliderUintHandle("TRAIL_FREQUENCY")
throttle0 = flr.getSliderFloatHandle("THROTTLE0")
throttle1 = flr.getSliderFloatHandle("THROTTLE1")
throttle2 = flr.getSliderFloatHandle("THROTTLE2")
throttle3 = flr.getSliderFloatHandle("THROTTLE3")

resetButton = flr.getButtonHandle("RESET")

quadcopterController = None

wayPoints = None
def initResources():
  global wayPoints
  wayPoints = []
  for i in range(wayPointCount):
    wayPoints.append(np.array([
      600.0 * random.random() - 300.0, 
      300.0 * random.random() + 100.0, 
      600.0 * random.random() - 300.0]))

  buf = bytearray(wayPointCount * 16)
  for i in range(wayPointCount):
    wp = wayPoints[i]
    buf[16*i:16*i+16] = struct.pack("<ffff", wp[0], wp[1], wp[2], 1.0)
  flr.cmdBufferStagedUpload(wayPointsHandle, 0, buf)

  defaultNodeMaterial = flr.getConstUint("MATERIAL_SLOT_NODES")
  motorMaterialStart = flr.getConstUint("MATERIAL_SLOT_MOTOR0")
  buf = bytearray(pbd.nodeCount * 4)
  for i in range(pbd.nodeCount):
    buf[4*i:4*i+4] = struct.pack("<I", defaultNodeMaterial)
  
  for motorIdx in range(4):
    matIdx = motorMaterialStart + motorIdx
    for nodeIdx in motorShapes[motorIdx].nodeIndices:
      buf[4*nodeIdx:4*nodeIdx+4] = struct.pack("<I", matIdx)

  flr.cmdBufferStagedUpload(nodeMaterialsHandle, 0, buf)

  global quadcopterController
  quadcopterController = pid.QuadcopterController(flr)

initResources()

def uploadPositions():
  posOffs = pbd.getGlobalCenterOfMass() if pinToOrigin.get() else np.zeros(3)
  buf = bytearray(pbd.nodeCount * 4 * 3)
  for i in range(pbd.nodeCount):
    pos = pbd.nodePositions[i] - posOffs
    buf[12*i:12*(i+1)] = struct.pack("<fff", pos[0], pos[1], pos[2])
  flr.cmdBufferWrite(positionsHandle, 0xFFFFFFFF, 0, buf)

def uploadThrottleData():
  buf = struct.pack("<ffff", motorInputs[0].throttle, motorInputs[1].throttle, motorInputs[2].throttle, motorInputs[3].throttle)
  flr.cmdBufferWrite(throttlesBufferHandle, 0xFFFFFFFF, 0, buf)

prevGizmoPos = np.zeros(3)
def addGizmo(tr, rot):
  global gizmoViewEnd
  global prevGizmoPos
  diff = tr - prevGizmoPos
  if np.dot(diff,diff) < 0.5:
    return
  buf = bytearray(64)
  buf[0:16] = struct.pack("<ffff", rot[0][0], rot[1][0], rot[2][0], 0.0)
  buf[16:32] = struct.pack("<ffff", rot[0][1], rot[1][1], rot[2][1], 0.0)
  buf[32:48] = struct.pack("<ffff", rot[0][2], rot[1][2], rot[2][2], 0.0)
  buf[48:64] = struct.pack("<ffff", tr[0], tr[1], tr[2], 1.0)
  offs = gizmoViewEnd % maxGizmoCount
  flr.cmdBufferWrite(gizmoBufferHandle, 0, offs * 64, buf)
  gizmoViewEnd += 1
  prevGizmoPos = tr

def updateGizmos():
  global gizmoViewStart
  buf = bytearray(8)
  buf[:] = struct.pack("<II", gizmoViewStart, gizmoViewEnd)
  flr.cmdBufferWrite(gizmoViewHandle, 0xFFFFFFFF, 0, buf)
  usedCount = gizmoViewEnd - gizmoViewStart
  if usedCount == maxGizmoCount:
    gizmoViewStart += 1

frame = 0
wpIdx = 0
while True:  
  if resetButton.get():
    initScene()
    gizmoViewStart = gizmoViewEnd
    quadcopterController = pid.QuadcopterController(flr)

  if enableFlightController.get():
    quadcopterController.targetPos = wayPoints[wpIdx]
    diff = pbd.nodePositions[0] - quadcopterController.targetPos
    dist = np.linalg.norm(diff)
    if dist < 10.0:
      wpIdx = (wpIdx + 1) % wayPointCount
      quadcopterController.targetPos = wayPoints[wpIdx]
    
    throttleSolution = quadcopterController.evaluate(body.centerOfMass, body.rotation, pbd.DT)
    for i in range(4):
      motorInputs[i].setThrottle(throttleSolution[i])
    
  elif testMotorsCheckbox.get():
    quadcopterController.reset()
    motorInputs[0].setThrottle(0.1 * math.sin(pbd.time))
    motorInputs[1].setThrottle(0.1 * math.sin(1.3 * pbd.time + 2))
    motorInputs[2].setThrottle(0.1 * math.sin(2.12 * pbd.time + 1))
    motorInputs[3].setThrottle(0.1 * math.sin(0.9 * pbd.time + 3.1))
  else:    
    quadcopterController.reset()
    motorInputs[0].setThrottle(throttle0.get())
    motorInputs[1].setThrottle(throttle1.get())
    motorInputs[2].setThrottle(throttle2.get())
    motorInputs[3].setThrottle(throttle3.get())

  if logFrequency.get() > 0 and frame%(30 * logFrequency.get()) == 0:
    printSensorLogs()
  
  if trailFrequency.get() == 0:
    gizmoViewStart = gizmoViewEnd
  elif frame%(3*trailFrequency.get()) == 0:
    # for s in pbd.shapes:
    #   addGizmo(s.centerOfMass, s.rotation)
    addGizmo(body.centerOfMass, body.rotation)
  
  # if flr.getCheckbox(pinToOrigin):
  #   pbd.rebaseToOrigin()
  pbd.disableFloorCollisions = disableFloor.get()
  if simulateCheckbox.get():
    pbd.stepSimulation()

  uploadPositions()
  updateGizmos()
  uploadThrottleData()
  match flr.tick():
    case flrlib.FlrTickResult.TR_REINIT:
      initScene()
      initResources()
    case flrlib.FlrTickResult.TR_TERMINATE:
      break
  frame += 1

exit(0) 