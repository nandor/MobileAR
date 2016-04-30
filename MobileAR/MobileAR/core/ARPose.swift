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
  
  /**
   Initializer to create a translation matrix.
   */
  init(t: float3) {
    self.init([
        float4(  1,   0,   0, 0),
        float4(  0,   1,   0, 0),
        float4(  0,   0,   1, 0),
        float4(t.x, t.y, t.z, 1)
    ])
  }
  
  /**
   Initializer to create a rotation matrix around X.
   */
  init(rx: Float) {
    self.init([
      float4(1, 0, 0, 0),
      float4(0, +cos(rx), +sin(rx), 0),
      float4(0, -sin(rx), +cos(rx), 0),
      float4(0, 0, 0, 1)
    ])
  }
  
  /**
   Initializer to create a rotation matrix around X.
   */
  init(ry: Float) {
    self.init([
      float4(+cos(ry), 0, -sin(ry), 0),
      float4(0, 1, 0, 0),
      float4(+sin(ry), 0, +cos(ry), 0),
      float4(0, 0, 0, 1)
    ])
  }
  
  /**
   Initializer to create a rotation matrix around X.
   */
  init(rz: Float) {
    self.init([
      float4(+cos(rz), +sin(rz), 0, 0),
      float4(-sin(rz), +cos(rz), 0, 0),
      float4(0, 0, 1, 0),
      float4(0, 0, 0, 1)
    ])
  }
}


/**
 Represents a pose.
 */
@objc class ARPose : NSObject {
  
  /// View matrix.
  let viewMat: float4x4
  
  /// Projection matrix.
  let projMat: float4x4
  
  /**
   Initializes the pose.
   */
  required init(viewMat: float4x4, projMat: float4x4) {
    self.viewMat = viewMat
    self.projMat = projMat
  }
  
  /**
   Creates a pose from Objc matrices.
   */
  convenience init(r: matrix_float4x4, p: matrix_float4x4) {
    self.init(viewMat: float4x4(r), projMat: float4x4(p))
  }
  
  /**
   Creates a pose using a user-defined projection matrix.
   */
  convenience init(
      projMat: float4x4,
      rx: Float,
      ry: Float,
      rz: Float,
      tx: Float,
      ty: Float,
      tz: Float)
  {
    self.init(
        viewMat: (
            float4x4(t: float3(tx, ty, tz)) *
            float4x4(rx: rx) *
            float4x4(ry: ry) *
            float4x4(rz: rz)
        ),
        projMat: projMat
    )
  }
  
  /**
   Creates a pose using the OpenCV projection paramters.
   */
  convenience init(
      params: ARParameters,
      rx: Float,
      ry: Float,
      rz: Float,
      tx: Float,
      ty: Float,
      tz: Float)
  {
    self.init(
        projMat: float4x4([
            float4(2 * params.fx, 0, 0, 0),
            float4(0, 2 * params.fy, 0, 0),
            float4(2 * params.cx, 2 * params.cy, 1, 0),
            float4(0, 0, 0, 1)
        ]),
        rx: rx,
        ry: ry,
        rz: rz,
        tx: tx,
        ty: ty,
        tz: tz
    )
  }
  
  /**
   Creates a pose from matrices stored in column-major order.
   */
 @objc convenience init(viewMat: [Float], projMat: [Float]) {
    self.init(
      viewMat: float4x4([
            float4(viewMat[ 0], viewMat[ 1], viewMat[ 2],  viewMat[ 3]),
            float4(viewMat[ 4], viewMat[ 5], viewMat[ 6],  viewMat[ 7]),
            float4(viewMat[ 8], viewMat[ 9], viewMat[10],  viewMat[11]),
            float4(viewMat[12], viewMat[13], viewMat[14],  viewMat[15])
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
  
  // Objective-C accesors.
  @objc var view: matrix_float4x4 { get { return viewMat.cmatrix } }
  @objc var proj: matrix_float4x4 { get { return projMat.cmatrix } }
}
