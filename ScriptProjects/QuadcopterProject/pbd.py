
import numpy as np

# Encapsulate into PbdScene class
nodeCount = 0  
nodePositions = np.array([])
shapes = []
fixedNodes = []
motors = []
rotors = []

disableFloorCollisions = False

def resetScene():
  global nodeCount
  global nodePositions
  global shapes
  global fixedNodes
  global motors
  global rotors
  nodeCount = 0  
  nodePositions = np.array([])
  shapes = []
  fixedNodes = []
  motors = []
  rotors = []

def createNode(pos):
  global nodeCount
  global nodePositions
  idx = nodeCount
  nodePositions = np.append(nodePositions, pos)
  nodeCount += 1
  return idx

class Shape:
  def __init__(self):
    self.nodeIndices = []
    self.centerOfMass = np.array([0.0, 0.0, 0.0])
    self.rotation = np.identity(3)
    self.nodeLocalPositions = np.array([])

  def addNode(self, idx):
    self.nodeIndices.append(idx)

  def addNewNode(self, pos):
    nodeIdx = nodeCount
    self.addNode(createNode(pos))
    return nodeIdx

class FixedNode:
  def __init__(self, idx, fixedPos):
    self.nodeIdx = idx
    self.fixedPos = fixedPos

class Rotor:
  def __init__(self, shape : Shape, nodeIdx, dir, power, clockwise):
    for i in range(len(shape.nodeIndices)):
      if nodeIdx == shape.nodeIndices[i]:
        self.localNodeIdx = i
        break
    else:
      assert(False)
    self.shape = shape
    self.dir = dir
    self.power = power
    self.clockwise = clockwise
    self.throttle = 0.0
  
  def setThrottle(self, throttle : float):
    self.throttle = throttle

class Motor:
  def __init__(self, originIdx, upIdx, leftIdx, rightIdx, power, clockwise):
    self.originIdx = originIdx
    self.upIdx = upIdx
    self.leftIdx = leftIdx
    self.rightIdx = rightIdx
    self.power = power
    self.clockwise = clockwise
    self.throttle = 0.0

  def setThrottle(self, amt : float):
    self.throttle = amt

def createBox(pos, halfDims):
  box = Shape()
  pos = np.array(pos)
  halfDims = np.array(halfDims)
  for i in range(2):
    for j in range(2):
      for k in range(2):
        box.addNewNode(pos - halfDims + 2 * np.array([i, j, k]) * halfDims)
  shapes.append(box)
  return box

def createShape():
  s = Shape()
  shapes.append(s)
  return s

# TODO - would be better to have a parent shape, along with a src node and local axis
# TODO - want to be able to add torque effect on body from motor
def createMotor(originIdx : int, upIdx : int, leftIdx : int, rightIdx : int, power : float, clockwise : bool):
  m = Motor(originIdx, upIdx, leftIdx, rightIdx, power, clockwise)
  motors.append(m)
  return m

def createRotor(shape : Shape, nodeIdx : int, dir, power : float, clockwise : bool):
  r = Rotor(shape, nodeIdx, dir, power, clockwise)
  rotors.append(r)
  return r

def addFixedNode(idx : int):
  fn = FixedNode(idx, nodePositions[idx])
  fixedNodes.append(fn)

nodePrevPositions = []
nodeVelocities = []

def finalizeScene():
  global nodePositions
  global nodePrevPositions
  global nodeVelocities
  nodePositions = nodePositions.reshape(nodeCount, 3)
  nodePrevPositions = np.zeros((nodeCount, 3))
  nodePrevPositions[:] = nodePositions[:]
  nodeVelocities = np.zeros((nodeCount, 3))

  for shape in shapes:
    localNodeCount = len(shape.nodeIndices)
    shape.centerOfMass = np.zeros(3)
    for nodeIdx in shape.nodeIndices:
      shape.centerOfMass += nodePositions[nodeIdx] / localNodeCount
    shape.nodeLocalPositions = np.zeros((localNodeCount, 3))
    for i in range(localNodeCount):
      nodeIdx = shape.nodeIndices[i]
      shape.nodeLocalPositions[i] = nodePositions[nodeIdx] - shape.centerOfMass

def getGlobalCenterOfMass():
  com = np.zeros(3)
  for nodeIdx in range(nodeCount):
    com += nodePositions[nodeIdx]
  com /= nodeCount
  return com

def rebaseToOrigin():
  com = getGlobalCenterOfMass()  
  for nodeIdx in range(nodeCount):
    nodePositions[nodeIdx] -= com
    nodePrevPositions[nodeIdx] -= com

time = 0.0
DT = 1.0 / 30.0
GRAVITY = 20.0
floorHeight = -25.0

kFloor = 0.99
kShape = 0.99
kFixed = 0.99
kFriction = 0.9

def applyImpulse(nodeIdx, p):
  nodeVelocities[nodeIdx] += p

def stepSimulation():
  global nodePositions
  global nodePrevPositions
  global nodeVelocities
  nodeVelocities[:] = (nodePositions - nodePrevPositions) / DT
  for i in range(nodeCount):
    nodeVelocities[i][1] += -GRAVITY * DT

  for m in motors:
    # TODO check for degenerate case
    motorDir = nodePositions[m.upIdx] - nodePositions[m.originIdx]
    motorDir /= np.linalg.norm(motorDir)
    motorRef = nodePositions[m.rightIdx] - nodePositions[m.originIdx]
    motorRef /= np.linalg.norm(motorRef) 
    perpDir = np.cross(motorRef, motorDir)
    if m.clockwise:
      perpDir *= -1.0
    p = m.power * m.throttle * motorDir * DT
    # nodeVelocities[m.fromIdx] += p
    nodeVelocities[m.upIdx] += p
    perpVel = m.power * m.throttle * perpDir * DT
    nodeVelocities[m.leftIdx] += perpVel
    nodeVelocities[m.rightIdx] -= perpVel
  
  for r in rotors:
    nodeIdx = r.shape.nodeIndices[r.localNodeIdx]
    localPos = r.shape.nodeLocalPositions[r.localNodeIdx]
    rotorPos = (r.shape.rotation @ localPos) + r.shape.centerOfMass
    rotorDir = r.shape.rotation @ r.dir
    p = r.power * r.throttle * rotorDir * DT
    for idx in r.shape.nodeIndices:
      diff = nodePositions[idx] - rotorPos
      perp = diff - rotorDir * np.dot(rotorDir, diff)
      # TODO cross product probably already does this above line...
      nodeVelocities[idx] += (-1.0 if r.clockwise else 1.0) * np.cross(perp, p)
      # nodeVelocities[idx] += p
    nodeVelocities[nodeIdx] += p
    
  nodePrevPositions[:] = nodePositions[:]
  # prediction
  nodePositions[:] += nodeVelocities * DT

  # constraints
    
  # floor constraint
  if not disableFloorCollisions:
    for i in range(nodeCount):
      h = floorHeight - nodePositions[i][1]
      if h > 0:
        nodePositions[i][1] += kFloor * h
        # friction damps perp velocity
        errDiff = nodePrevPositions[i] - nodePositions[i]
        errDiff[1] = 0.0
        nodePositions[i] += kFriction * errDiff 

  for shape in shapes:
    localNodeCount = len(shape.nodeIndices)
    shape.centerOfMass = np.zeros(3)
    for idx in shape.nodeIndices:
      shape.centerOfMass += nodePositions[idx] / localNodeCount
    
    v1 = np.zeros((localNodeCount, 3))
    for i in range(localNodeCount):
      idx = shape.nodeIndices[i]
      v1[i] = nodePositions[idx] - shape.centerOfMass
    
    H = np.dot(shape.nodeLocalPositions.T, v1)
    U, S, Vt = np.linalg.svd(H)
    shape.rotation = Vt.T @ U.T
    
    v1 = shape.rotation @ shape.nodeLocalPositions.T

    for i in range(localNodeCount):
      idx = shape.nodeIndices[i]
      projPos = v1.T[i] + shape.centerOfMass
      errDiff = projPos - nodePositions[idx]
      nodePositions[idx] += kShape * errDiff
    
  for fn in fixedNodes:
    errDiff = fn.fixedPos - nodePositions[fn.nodeIdx]
    nodePositions[fn.nodeIdx] += kFixed * errDiff
  
  global time
  time += DT






