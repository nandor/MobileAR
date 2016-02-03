// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import simd


/**
 Helper method to create a projection matrix.
 */
extension float4x4 {
  /**
   Initializer to create a projection matrix.
   */
  init(aspect: Float, fov: Float, n: Float, f: Float) {
    let tanFOV = Float(tan((Double(fov) / 180.0 * M_PI) / 2.0))
    let yScale = 1.0 / tanFOV
    let xScale = 1.0 / (aspect * tanFOV)
  
    self.init([
        float4(xScale, 0, 0, 0),
        float4(0, yScale, 0, 0),
        float4(0, 0, (f + n) / (n - f), -1),
        float4(0, 0, 2 * n * f / (n - f), 0)
    ])
  }
}


/**
 Represents a pose.
 */
@objc class ARPose : NSObject {
  let viewMat: float4x4
  let projMat: float4x4

  required init(viewMat: float4x4, projMat: float4x4) {
    self.viewMat = viewMat
    self.projMat = projMat
  }

  convenience init(
      projMat: float4x4,
      rx: Float,
      ry: Float,
      rz: Float,
      tx: Float,
      ty: Float,
      tz: Float)
  {
    // Pitch.
    let rotX = float4x4([
      float4(+cos(rx), 0, -sin(rx), 0),
      float4(0, 1, 0, 0),
      float4(+sin(rx), 0, +cos(rx), 0),
      float4(0, 0, 0, 1)
    ])
    
    // Yaw.
    let rotY = float4x4([
      float4(+cos(ry), +sin(ry), 0, 0),
      float4(-sin(ry), +cos(ry), 0, 0),
      float4(0, 0, 1, 0),
      float4(0, 0, 0, 1)
    ])
    
    // Roll.
    let rotZ = float4x4([
      float4(1, 0, 0, 0),
      float4(0, +cos(rz), +sin(rz), 0),
      float4(0, -sin(rz), +cos(rz), 0),
      float4(0, 0, 0, 1)
    ])
    
    // Translation.
    let trans = float4x4([
      float4(1, 0, 0, 0),
      float4(0, 1, 0, 0),
      float4(0, 0, 1, 0),
      float4(tx, ty, tz, 1)
    ])
    
    self.init(
      viewMat: trans * rotZ * rotX * rotY,
      projMat: projMat
    )
  }
  
  convenience init(
      params: ARParameters,
      rx: Float,
      ry: Float,
      rz: Float,
      tx: Float,
      ty: Float,
      tz: Float)
  {
    // Compute the projection matrix.
    let f: Float = 100.0
    let n: Float = 0.1

    self.init(
        projMat: float4x4([
            float4(params.fx / params.cx, 0, 0, 0),
            float4(0, params.fy / params.cy, 0, 0),
            float4(0, 0, (f + n) / (n - f), -1),
            float4(0, 0, 2 * n * f / (n - f), 0)
        ]),
        rx: rx,
        ry: ry,
        rz: rz,
        tx: tx,
        ty: ty,
        tz: tz
    )
  }
  
 convenience init(viewMat: [Float], projMat: [Float]) {
    
    // Story time. OpenCV's matrix was calibrated such that the marker is on
    // a plane with z = 0, which means that y must be swapped with z. Also,
    // y must be inverted and after applying transformation, the handedness
    // of the system must be corrected by inverting the direction of y and z
    // to match the orientation of the display and the depth buffer.
    self.init(
        viewMat: float4x4([
            float4(1,  0,  0, 0),
            float4(0, -1,  0, 0),
            float4(0,  0, -1, 0),
            float4(0,  0,  0, 1)
        ]) * float4x4([
            float4(viewMat[ 0], viewMat[ 1], viewMat[ 2], viewMat[ 3]),
            float4(viewMat[ 4], viewMat[ 5], viewMat[ 6], viewMat[ 7]),
            float4(viewMat[ 8], viewMat[ 9], viewMat[10], viewMat[11]),
            float4(viewMat[12], viewMat[13], viewMat[14], viewMat[15])
        ]) * float4x4([
            float4(1,  0,  0, 0),
            float4(0,  0, -1, 0),
            float4(0,  1,  0, 0),
            float4(0,  0,  0, 1)
        ]),
        projMat: float4x4([
            float4(projMat[ 0], projMat[ 1], projMat[ 2], projMat[ 3]),
            float4(projMat[ 4], projMat[ 5], projMat[ 6], projMat[ 7]),
            float4(projMat[ 8], projMat[ 9], projMat[10], projMat[11]),
            float4(projMat[12], projMat[13], projMat[14], projMat[15])
        ])
    )
  }

  /**
   Performs a reverse projection, from screen space to world space.
   */
  @objc func unproject(v: float3) -> float3 {
    let w = viewMat.inverse * projMat.inverse * float4(v.x, v.y, v.z, 1.0)
    return float3(w.x / w.w, w.y / w.w, w.z / w.w)
  }
}
