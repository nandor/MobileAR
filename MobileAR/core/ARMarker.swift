// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import simd
import UIKit


/**
 Class representing an on-screen marker.
 */
@objc class ARMarker : NSObject {

  // The four corner points.
  let p0: float2
  let p1: float2
  let p2: float2
  let p3: float2

  /**
   Creates a new with a homography and corners.
   */
  @objc init(p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) {
    
    self.p0 = float2(Float(p0.x), Float(p0.y))
    self.p1 = float2(Float(p1.x), Float(p1.y))
    self.p2 = float2(Float(p2.x), Float(p2.y))
    self.p3 = float2(Float(p3.x), Float(p3.y))
  }
}
