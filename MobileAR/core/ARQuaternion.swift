// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import simd

class ARQuaternion {
  let w: Float
  let v: float3
  
  /**
   Initializes the quaternion from a scalar and a vector part.
   */
  required init(w: Float, v: float3) {
    self.w = w
    self.v = v
  }
  
  /**
   Creates a quaternion, providing all components.
   */
  convenience init(w: Float, x: Float, y: Float, z: Float) {
    self.init(w: w, v: float3(x, y, z))
  }
  
  /**
   Creates a unit quaternion representing an axis-angle rotation.
   */
  convenience init(axis: float3, angle: Float) {
    precondition(length(axis) == 1, "Axis must be of unit length")
    let halfAngle = angle / 2
    self.init(w: cos(halfAngle), v: sin(halfAngle) * axis)
  }
  
  // Create a quaternion from a principal axis and an angle.
  convenience init(rotX: Float) {
    self.init(axis: float3(1, 0, 0), angle: rotX)
  }
  convenience init(rotY: Float) {
    self.init(axis: float3(0, 1, 0), angle: rotY)
  }
  convenience init(rotZ: Float) {
    self.init(axis: float3(0, 0, 1), angle: rotZ)
  }
  
  // Accessors for Objective-C.
  @objc var x: Float { get { return v.x } }
  @objc var y: Float { get { return v.y } }
  @objc var z: Float { get { return v.z } }
}

func * (left: ARQuaternion, right: ARQuaternion) -> ARQuaternion {
  return ARQuaternion(
      w: left.w * right.w - dot(left.v, right.v),
      v: left.w * right.v + right.w * left.v - cross(left.v, right.v)
  )
}