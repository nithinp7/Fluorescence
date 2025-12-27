
import numpy as np
import quaternion as q
import flrlib

# TODO a better interface for bindable values...

class PidController:
  def __init__(self, flr : flrlib.FlrScriptInterface, name : str):
    self.kProp = flr.getSliderFloatHandle(name + "_PROP")
    self.kDiff = flr.getSliderFloatHandle(name + "_DIFF")
    self.kInt = flr.getSliderFloatHandle(name + "_INT")
    self.accumErr = 0.0

  def reset(self):
    self.accumErr = 0.0

  def evaluate(self, flr : flrlib.FlrScriptInterface, err : float, vel : float):
    response = self.kProp.get() * err - self.kDiff.get() * vel + self.kInt.get() * self.accumErr
    self.accumErr += err
    return response

class QuadcopterController:
  def __init__(self, flr : flrlib.FlrScriptInterface):
    self.targetHeight = 20.0
    self.targetFrontVelocity = 0.0
    self.targetSideVelocity = 0.0
    self.targetYawVelocity = 0.0
    self.targetRotation = q.quaternion(1, 0, 0, 0)
    
    self.prevTransformValid = False
    self.prevTranslation = np.zeros(3)
    self.prevRotation = q.quaternion(1, 0, 0, 0)

    self.altController = PidController(flr, "ALT")
    self.pitchController = PidController(flr, "ROT")
    self.rollController = PidController(flr, "ROT")
    self.yawController = PidController(flr, "ROT")

  def reset(self):
    self.prevTransformValid = False
    self.prevTranslation = np.zeros(3)
    self.prevRotation = q.quaternion(1, 0, 0, 0)

    self.altController.reset()
    self.pitchController.reset()
    self.rollController.reset()
    self.yawController.reset()

  def evaluate(self, flr : flrlib.FlrScriptInterface, translation, rotationMatrix, dt):
    rotation = q.from_rotation_matrix(rotationMatrix)

    solution = np.zeros(4)
    if not self.prevTransformValid:
      self.prevTranslation[:] = translation[:]
      self.prevRotation = rotation
      self.prevTransformValid = True
      return solution
    
    rotation, self.prevRotation = q.unflip_rotors([rotation, self.prevRotation])
    
    currentTilt = rotationMatrix[:][1]

    linearVelocity = (translation - self.prevTranslation) / dt
    altituteError = self.targetHeight - translation[1]
    thrust = self.altController.evaluate(flr, altituteError, linearVelocity[1])
    thrust *= currentTilt[1] # np.clip(currentTilt[1], 0.0, 1.0)
    # thrust = np.clip(thrust, -8.5, 8.5)

    # TODO add longer rotation history...
    # 0/1+ tilts towards x-axis (clockwise around z)
    # 1/2+ tilts away from z-axis (clockwise around x)
    angVelocity = q.angular_velocity([self.prevRotation, rotation], [0.0, dt])[1]
    angVelocity = q.rotate_vectors(rotation.conjugate(), angVelocity)

    # TODO introduce a tilt-controller...
    targetTilt = np.array([0.0, 1.0, 0.0])
    
    targetTilt[0] = np.clip(0.1 * translation[0], -0.25, 0.25)
    targetTilt[2] = np.clip(0.1 * translation[2], -0.25, 0.25)

    targetTilt /= np.linalg.norm(targetTilt)

    tiltCrs = np.cross(targetTilt, currentTilt)
    tiltCrs = q.rotate_vectors(rotation.conjugate(), tiltCrs)

    pitch = self.pitchController.evaluate(flr, tiltCrs[2], angVelocity[2])
    roll = self.rollController.evaluate(flr, tiltCrs[0], angVelocity[0])
    yaw = self.yawController.evaluate(flr, tiltCrs[1], angVelocity[1])
    
    solution[0] = thrust - pitch + roll - yaw
    solution[1] = thrust - pitch - roll + yaw
    solution[2] = thrust + pitch - roll - yaw 
    solution[3] = thrust + pitch + roll - yaw

    solution = np.clip(solution / 10.0, -1.0, 1.0)

    self.prevTranslation[:] = translation[:]
    self.prevRotation = rotation

    return solution