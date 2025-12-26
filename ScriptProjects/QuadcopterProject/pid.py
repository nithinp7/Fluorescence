
import numpy as np
import quaternion as q

# some dummy values for now
targetHeight = 0.0
targetFrontVelocity = 0.0
targetSideVelocity = 0.0

kProp = 1.0
kDiff = 1.0
kInt = 0.0

kTiltProp = 1.0
kTiltDiff = 1.0
kTiltInt = 0.0

prevTransformValid = False
prevTranslation = np.zeros(3)
prevRotation = q.quaternion(1, 0, 0, 0)

accumHeightErr = 0.0
accumTiltFrontErr = 0.0
accumTiltSideErr = 0.0


def reset():
  global prevTransformValid
  global prevTranslation
  global prevRotation
  global accumHeightErr
  global accumTiltFrontErr
  global accumTiltSideErr

  prevTransformValid = False
  prevTranslation = np.zeros(3)
  prevRotation = q.quaternion(1, 0, 0, 0)

  accumHeightErr = 0.0
  accumTiltFrontErr = 0.0
  accumTiltSideErr = 0.0

def update(translation, rotationMatrix, dt):
  global prevTransformValid
  global accumHeightErr
  global prevTranslation
  global prevRotation
  global accumTiltFrontErr
  global accumTiltSideErr

  rotation = q.from_rotation_matrix(rotationMatrix)

  solution = np.zeros(4)
  if not prevTransformValid:
    prevTranslation[:] = translation[:]
    prevRotation = rotation
    prevTransformValid = True
    return solution
  
  rotation, prevRotation = q.unflip_rotors([rotation, prevRotation])
  
  linearVelocity = (translation - prevTranslation) / dt
  linearError = targetHeight - translation[1]
  for i in range(4):
    solution[i] += kProp * linearError - kDiff * linearVelocity[1] + kInt * accumHeightErr
  accumHeightErr += linearError

  # TODO add longer rotation history...
  # 0/1+ tilts towards x-axis (clockwise around z)
  # 1/2+ tilts away from z-axis (clockwise around x)
  angVelocity = q.angular_velocity([prevRotation, rotation], [0.0, dt])[1]
  angVelocity = q.rotate_vectors(rotation.conjugate(), angVelocity)
  frontTiltErr = angVelocity[2] - targetFrontVelocity
  for i in range(4):
    sn = -1.0 if i < 2 else 1.0
    solution[i] += sn * (-kTiltDiff * frontTiltErr + kTiltInt * accumTiltFrontErr)
  accumTiltFrontErr += frontTiltErr

  sideTiltErr = angVelocity[0] - targetSideVelocity
  for i in range(4):
    sn = -1.0 if i == 1 or i == 2 else 1.0
    solution[i] += sn * (-kTiltDiff * sideTiltErr + kTiltInt * accumTiltSideErr)
  accumTiltSideErr += sideTiltErr
  # print(f"ANG VELOCITY: ({angVelocity[0]}, {angVelocity[1]}, {angVelocity[2]})")
  
  solution = np.clip(solution / 10.0, -1.0, 1.0)

  prevTranslation[:] = translation[:]
  prevRotation = rotation

  return solution