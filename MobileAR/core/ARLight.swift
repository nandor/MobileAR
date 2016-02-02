// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import Foundation
import simd

/**
 Represents a directional light source.
 */
struct ARLight {
  /// Position of the light.
  var direction: float4

  /// Ambient component.
  var ambient: float4
  
  /// Diffuse component.
  var diffuse: float4
  
  /// Specular component.
  var specular: float4
}