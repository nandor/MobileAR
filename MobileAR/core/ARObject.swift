// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import Foundation

/**
 Object that can be rendered, holds an IBO and a VBO.
 */
class ARObject {

  // Index Buffer Object.
  var ibo: MTLBuffer!

  // Vertex Buffer Object.
  var vbo: MTLBuffer!

  // Number of indices.
  var indices: Int!

  /**
   Initializes the mesh.
   */
  init(device: MTLDevice) {

    // Set up the vertex buffer.
    var vboData: [Float] = [
      -1, -1, -1, -1,  0,  0,  0, 0,
      -1, -1,  1, -1,  0,  0,  0, 1,
      -1,  1,  1, -1,  0,  0,  1, 1,
      -1,  1, -1, -1,  0,  0,  1, 0,

       1, -1, -1,  1,  0,  0,  0, 0,
       1, -1,  1,  1,  0,  0,  0, 1,
       1,  1,  1,  1,  0,  0,  1, 1,
       1,  1, -1,  1,  0,  0,  1, 0,

      -1, -1, -1,  0, -1,  0,  0, 0,
      -1, -1,  1,  0, -1,  0,  0, 1,
       1, -1,  1,  0, -1,  0,  1, 1,
       1, -1, -1,  0, -1,  0,  1, 0,

      -1,  1, -1,  0,  1,  0,  0, 0,
      -1,  1,  1,  0,  1,  0,  0, 1,
       1,  1,  1,  0,  1,  0,  1, 1,
       1,  1, -1,  0,  1,  0,  1, 0,

      -1, -1, -1,  0,  0, -1,  0, 0,
      -1,  1, -1,  0,  0, -1,  0, 1,
       1,  1, -1,  0,  0, -1,  1, 1,
       1, -1, -1,  0,  0, -1,  1, 0,

      -1, -1,  1,  0,  0,  1,  0, 0,
      -1,  1,  1,  0,  0,  1,  0, 1,
       1,  1,  1,  0,  0,  1,  1, 1,
       1, -1,  1,  0,  0,  1,  1, 0,
    ];
    vbo = device.newBufferWithBytes(
      vboData,
      length: sizeofValue(vboData[0]) * vboData.count,
      options: MTLResourceOptions()
    )

    // Set up the index buffer.
    var iboData: [UInt32] = [
       0 + 0,  0 + 2,  0 + 1,  0 + 0,  0 + 3,  0 + 2,
       4 + 0,  4 + 1,  4 + 2,  4 + 0,  4 + 2,  4 + 3,
       8 + 0,  8 + 1,  8 + 2,  8 + 0,  8 + 2,  8 + 3,
      12 + 0, 12 + 2, 12 + 1, 12 + 0, 12 + 3, 12 + 2,
      16 + 0, 16 + 2, 16 + 1, 16 + 0, 16 + 3, 16 + 2,
      20 + 0, 20 + 1, 20 + 2, 20 + 0, 20 + 2, 20 + 3,
    ]
    ibo = device.newBufferWithBytes(
      iboData,
      length: sizeofValue(iboData[0]) * iboData.count,
      options: MTLResourceOptions()
    )

    indices = iboData.count
  }
}

