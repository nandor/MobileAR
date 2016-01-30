// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import simd

/**
 Represents a SE3 pose.
 */
@objc class ARPose : NSObject {
  let viewMat: float4x4
  let projMat: float4x4
  
  init(viewMat: float4x4, projMat: float4x4) {
    self.viewMat = viewMat
    self.projMat = projMat
  }
  
  init(viewMat: [Float], projMat: [Float]) {
    
    // Story time. OpenCV's matrix was calibrated such that the marker is on
    // a plane with z = 0, which means that y must be swapped with z. Also,
    // y must be inverted and after applying transformation, the handedness
    // of the system must be corrected by inverting the direction of y and z
    // to match the orientation of the display and the depth buffer.
    self.viewMat = float4x4([
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
    ])
    self.projMat = float4x4([
      float4(projMat[ 0], projMat[ 1], projMat[ 2], projMat[ 3]),
      float4(projMat[ 4], projMat[ 5], projMat[ 6], projMat[ 7]),
      float4(projMat[ 8], projMat[ 9], projMat[10], projMat[11]),
      float4(projMat[12], projMat[13], projMat[14], projMat[15])
    ])
  }
}
