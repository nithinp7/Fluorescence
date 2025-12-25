
import numpy as np
import quaternion as q

# some dummy values for now
targetHeight = 0.0

kProp = 1.0
kDiff = 1.0
kInt = 0.0

prevTransformValid = False
prevTranslation = np.zeros(3)
prevRotation = q.quaternion(1, 0, 0, 0)

accumHeightErr = 0.0

def reset():
  global prevTransformValid
  global prevTranslation
  global prevRotation
  global accumHeightErr

  prevTransformValid = False
  prevTranslation = np.zeros(3)
  prevRotation = q.quaternion(1, 0, 0, 0)

  accumHeightErr = 0.0

def update(translation, rotation, dt):
  global prevTransformValid
  global accumHeightErr
  global prevTranslation
  global prevRotation

  solution = np.zeros(4)
  if not prevTransformValid:
    prevTranslation[:] = translation[:]
    prevRotation = q.from_rotation_matrix(rotation)
    prevTransformValid = True
    return solution
  
  # TODO 
  linearVelocity = (translation - prevTranslation)
  linearError = targetHeight - translation[1]
  for i in range(4):
    solution[i] += kProp * linearError - kDiff * linearVelocity[1] + kInt * accumHeightErr
  accumHeightErr += linearError

  solution = np.clip(solution / 10.0, -1.0, 1.0)

  prevTranslation[:] = translation[:]
  prevRotation = q.from_rotation_matrix(rotation)

  return solution