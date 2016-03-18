// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

/**
 Demo pose tracker that rotates the scene around the Y axis.
 */
@objc class ARDemoPoseTracker : NSObject, ARPoseTracker {
  /// Rotation angle around Y.
  private var angle: Float = 0.0
  /// Aspect ratio.
  private let aspect: Float

  /**
   Initializes the object.
   */
  init(aspect: Float) {
    self.aspect = aspect
  }

  /**
   No-op
   */
  func trackFrame(image: UIImage) {
  }

  /**
   No-op
   */
  func trackSensor(attitude: CMAttitude, acceleration: CMAcceleration) {
    angle += 0.01;
  }

  /**
   Returns a pose with a perspective projection.
   */
  func getPose() -> ARPose {
    return ARPose(
        projMat: float4x4(
            aspect: Float(aspect),
            fov: 45.0,
            n: 0.1,
            f: 100.0
        ),
        rx: 0.0,
        ry: angle,
        rz: 0.0,
        tx: 0.0,
        ty: -6.0,
        tz: -20.0
    )
  }
}
