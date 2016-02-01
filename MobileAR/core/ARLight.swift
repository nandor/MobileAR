// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import Foundation
import simd

/**
 Represents a directional light source.
 */
class ARLight : NSObject {
  
  /// Position of the light.
  let direction: float3;
  
  /// Ambient component.
  let ambient: float3
  
  /// Diffuse component.
  let diffuse: float3
  
  /// Specular component.
  let specular: float3
  
  /**
   Initializes the light source.
   */
  init(direction: float3, diffuse: float3, ambient: float3, specular: float3) {
    self.direction = direction
    self.diffuse = diffuse
    self.ambient = ambient
    self.specular = specular
  }
}