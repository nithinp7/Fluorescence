
import numpy as np
import quaternion as q
import flrlib

class PidController:
  def __init__(self, flr : flrlib.FlrScriptInterface, name : str):
    self.kEnable = flr.getCheckboxHandle(name + "_ENABLE")
    self.kProp = flr.getSliderFloatHandle(name + "_PROP")
    self.kDiff = flr.getSliderFloatHandle(name + "_DIFF")
    self.kInt = flr.getSliderFloatHandle(name + "_INT")
    self.accumErr = 0.0

  def reset(self):
    self.accumErr = 0.0

  def evaluate(self, err : float, vel : float):
    if self.kEnable.get():
      response = self.kProp.get() * err - self.kDiff.get() * vel + self.kInt.get() * self.accumErr
      self.accumErr += err
      return response
    else:
      self.accumErr = 0.0
      return 0.0

# TODO document the cascading PID design here...

class QuadcopterController:
  def __init__(self, flr : flrlib.FlrScriptInterface):
    self.targetPos = [
        flr.getSliderFloatHandle("TARGET_POS_X"),
        flr.getSliderFloatHandle("TARGET_POS_Y"),
        flr.getSliderFloatHandle("TARGET_POS_Z")]
    self.tiltLimit = flr.getSliderFloatHandle("TILT_LIMIT")
    self.targetCruiseSpeed = flr.getSliderFloatHandle("CRUISE_VEL")
    self.targetDeadband = flr.getSliderFloatHandle("TARGET_DEADBAND")
    self.altThrustLimit = flr.getSliderFloatHandle("ALT_THRUST_LIMIT")
    
    self.prevTransformValid = False
    self.prevTranslation = np.zeros(3)
    self.prevRotation = q.quaternion(1, 0, 0, 0)

    self.altController = PidController(flr, "ALT")
    self.tiltXController = PidController(flr, "TILT")
    self.tiltZController = PidController(flr, "TILT")
    self.pitchController = PidController(flr, "ROT")
    self.rollController = PidController(flr, "ROT")
    self.yawController = PidController(flr, "ROT")

  def reset(self):
    self.prevTransformValid = False
    self.prevTranslation = np.zeros(3)
    self.prevRotation = q.quaternion(1, 0, 0, 0)

    self.altController.reset()
    self.tiltXController.reset()
    self.tiltZController.reset()
    self.pitchController.reset()
    self.rollController.reset()
    self.yawController.reset()

  def evaluate(self, translation, rotationMatrix, dt):
    rotation = q.from_rotation_matrix(rotationMatrix)

    solution = np.zeros(4)
    if not self.prevTransformValid:
      self.prevTranslation[:] = translation[:]
      self.prevRotation = rotation
      self.prevTransformValid = True
      return solution
    
    rotation, self.prevRotation = q.unflip_rotors([rotation, self.prevRotation])
    
    linearVelocity = (translation - self.prevTranslation) / dt
    currentTilt = rotationMatrix[:][1]
    targetPos = np.array([x.get() for x in self.targetPos])
    posErr = targetPos - translation
    bInverted = currentTilt[1] < -0.2

    speedLimits = np.array([self.targetCruiseSpeed.get(), 0.0, self.targetCruiseSpeed.get()])
    targetVelocity = np.zeros(3)
    # TODO kind of a hack to keep the alt controller and tilt controller from fighting
    # think of a more natural way to have these coexist
    # if abs(posErr[1]) < 5.0:
    if not bInverted:
      targetVelocity = np.sign(posErr) * speedLimits * (np.ones(3) - np.exp(-posErr * posErr / 64.0 / self.targetDeadband.get()**2))
    velErr = linearVelocity - targetVelocity

    thrust = self.altController.evaluate(posErr[1], velErr[1])
    # if bInverted:
      # thrust *= -1.0
    thrust *= currentTilt[1] # 
    # thrust *= np.clip(currentTilt[1], 0.0, 1.0)
    altThrustLimit = self.altThrustLimit.get()
    if altThrustLimit > 0.0:
      thrust = np.clip(thrust, -altThrustLimit, altThrustLimit)
    reverseThrust = -1.0 if (thrust < 1.0 != bInverted) else 1.0
    # TODO 
    # - stabilize tilt limit, want to use larger limit for quick-stop flaring, but more conservative limit for cruising
    # - some of this can probably naturally be handled by using a linearVelocity - desiredVelocity for the diff term for tilting
    # - add a deadband region close to the target location so there isn't thrashing

    targetTilt = np.array([0.0, 1.0, 0.0])
    tiltLimit = self.tiltLimit.get()
    targetTilt[0] = reverseThrust * np.clip(self.tiltXController.evaluate(posErr[0], velErr[0]), -tiltLimit, tiltLimit)
    targetTilt[2] = reverseThrust * np.clip(self.tiltZController.evaluate(posErr[2], velErr[2]), -tiltLimit, tiltLimit)
    targetTilt /= np.linalg.norm(targetTilt)

    tiltCrs = np.cross(currentTilt, targetTilt)
    # if abs(np.dot(tiltCrs, tiltCrs)) <= 0.01 and np.dot(currentTilt, targetTilt) < 0.0:
    #   tiltCrs = np.array([1.0, 0.0, 0.0])
    tiltCrs = q.rotate_vectors(rotation.conjugate(), tiltCrs)

    # TODO add longer rotation history...
    # 0/1+ tilts towards x-axis (clockwise around z)
    # 1/2+ tilts away from z-axis (clockwise around x)
    angVelocity = q.angular_velocity([self.prevRotation, rotation], [0.0, dt])[1]
    angVelocity = q.rotate_vectors(rotation.conjugate(), angVelocity)

    pitch = self.pitchController.evaluate(tiltCrs[2], angVelocity[2])
    roll = self.rollController.evaluate(tiltCrs[0], angVelocity[0])
    yaw = self.yawController.evaluate(tiltCrs[1], angVelocity[1])
    
    # solution[0] = thrust - pitch + roll - yaw
    # solution[1] = thrust - pitch - roll + yaw
    # solution[2] = thrust + pitch - roll - yaw 
    # solution[3] = thrust + pitch + roll - yaw
    
    solution[0] = -pitch + roll - yaw
    solution[1] = -pitch - roll + yaw
    solution[2] = pitch - roll - yaw 
    solution[3] = pitch + roll + yaw

    solution += thrust - np.average(solution)

    solution = np.clip(solution / 10.0, -1.0, 1.0)

    self.prevTranslation[:] = translation[:]
    self.prevRotation = rotation

    return solution