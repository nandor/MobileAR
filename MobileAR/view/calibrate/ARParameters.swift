// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import Foundation

class ARParameters {
  let fx: Float
  let fy: Float
  let cx: Float
  let cy: Float
  let k1: Float
  let k2: Float
  let k3: Float
  let r1: Float
  let r2: Float

  required init(
    fx : Float,
    fy : Float,
    cx : Float,
    cy : Float,
    k1 : Float,
    k2 : Float,
    k3 : Float,
    r1 : Float,
    r2 : Float)
  {
    self.fx = fx
    self.fy = fy
    self.cx = cx
    self.cy = cy
    self.k1 = k1
    self.k2 = k2
    self.k3 = k3
    self.r1 = r1
    self.r2 = r2
  }

  static func load() -> ARParameters? {
    return ARParameters(
        fx: 0.0,
        fy: 0.0,
        cx: 0.0,
        cy: 0.0,
        k1: 0.0,
        k2: 0.0,
        k3: 0.0,
        r1: 0.0,
        r2: 0.0
    )
  }

  static func save(params: ARParameters) {
  }
}
