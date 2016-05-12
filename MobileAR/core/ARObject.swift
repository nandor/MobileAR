// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import simd

/**
 Information required to render a mesh.
 */
struct ARObject {
  /// Name of the mesh to be rendered.
  let mesh: String
  /// Model matrix of the mesh.
  let model: float4x4
}
