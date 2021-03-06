// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import Foundation
import simd

/**
 Represents a directional light source.
 */
@objc class ARLight : NSObject {
  /// Position of the light.
  let direction: float3
  /// Ambient component.
  let ambient: float3
  /// Diffuse component.
  let diffuse: float3
  /// Specular component.
  let specular: float3
  /// Position in the envmap.
  let x: Int
  let y: Int
  /// Area in the envmap.
  let area: Float

  init(
      direction: float3,
      ambient: float3,
      diffuse: float3,
      specular: float3,
      x: Int,
      y: Int,
      area: Float)
  {
    self.direction = direction
    self.ambient = ambient
    self.diffuse = diffuse
    self.specular = specular
    self.x = x
    self.y = y
    self.area = area
  }
}