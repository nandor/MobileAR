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
  func trackFrame(image: UIImage) -> Bool {
    return true
  }

  /**
   No-op
   */
  func trackSensor(x: CMAttitude, a: CMAcceleration, w: CMRotationRate) {
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
        rx: Float(-M_PI / 2.0 + 30.0 * M_PI / 180.0),
        ry: 0.0,
        rz: angle,
        tx: 0.0,
        ty: -5.0,
        tz: -25.0
    )
  }
}
