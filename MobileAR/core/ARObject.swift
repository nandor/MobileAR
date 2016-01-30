// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import Foundation
import simd

enum ARObjectError : ErrorType {
  case InvalidToken
}


/**
 Object that can be rendered, holds an IBO and a VBO.
 */
class ARObject {

  // Vertex Buffer Object.
  var vbo: MTLBuffer!

  // Number of indices.
  var indices: Int!
  
  // Index Buffer Object.
  var ibo: MTLBuffer?

  /**
   Initializes the mesh.
   */
  static func loadCube(device: MTLDevice) -> ARObject {
  
    // Set up the vertex buffer.
    let vboData: [Float] = [
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
  

    // Set up the index buffer.
    let iboData: [UInt32] = [
       0 + 0,  0 + 2,  0 + 1,  0 + 0,  0 + 3,  0 + 2,
       4 + 0,  4 + 1,  4 + 2,  4 + 0,  4 + 2,  4 + 3,
       8 + 0,  8 + 1,  8 + 2,  8 + 0,  8 + 2,  8 + 3,
      12 + 0, 12 + 2, 12 + 1, 12 + 0, 12 + 3, 12 + 2,
      16 + 0, 16 + 2, 16 + 1, 16 + 0, 16 + 3, 16 + 2,
      20 + 0, 20 + 1, 20 + 2, 20 + 0, 20 + 2, 20 + 3,
    ]
    
    let object = ARObject()
    object.vbo = device.newBufferWithBytes(
        vboData,
        length: sizeofValue(vboData[0]) * vboData.count,
        options: MTLResourceOptions()
    )
    object.ibo = device.newBufferWithBytes(
        iboData,
        length: sizeofValue(iboData[0]) * iboData.count,
        options: MTLResourceOptions()
    )
    object.indices = iboData.count
    return object
  }
  
  /**
   Loads an object from a Wavefront OBJ file.
   */
  static func loadObject(device: MTLDevice, url: NSURL) throws -> ARObject {
    
    var vv: [float3] = []
    var vn: [float3] = []
    var vt: [float2] = []
    var idx: [Int] = []
    
    // Read the data file.
    for line in try ARFileReader(url: url) {
      let t = line.componentsSeparatedByString(" ")
      switch (t[0]) {
        case "v":
          vv.append(float3(Float(t[1])!, Float(t[2])!, Float(t[3])!))
          break
        case "vn":
          vn.append(float3(Float(t[1])!, Float(t[2])!, Float(t[3])!))
          break
        case "vt":
          vt.append(float2(Float(t[1])!, Float(t[2])!))
          break
        case "f":
          for i in 1...3 {
            let verts = t[i].componentsSeparatedByString("/")
            idx.append(Int(verts[0])! - 1)
            idx.append(Int(verts[1])! - 1)
            idx.append(Int(verts[2])! - 1)
          }
          break
        case "#", "s":
          continue
        default:
          throw ARObjectError.InvalidToken
      }
    }
    
    // Build the vertex buffer.
    let indices = idx.count / 3
    var vbo = [Float](count: indices * 8, repeatedValue: 0.0)
    for var i = 0; i < indices; i += 1 {
      let vert = vv[idx[i * 3 + 0]]
      let norm = vn[idx[i * 3 + 2]]
      let uv = vt[idx[i * 3 + 1]]
      
      vbo[i * 8 + 0] = vert.x
      vbo[i * 8 + 1] = vert.y
      vbo[i * 8 + 2] = vert.z
      vbo[i * 8 + 3] = norm.x
      vbo[i * 8 + 4] = norm.y
      vbo[i * 8 + 5] = norm.z
      vbo[i * 8 + 6] = uv.x
      vbo[i * 8 + 7] = uv.x
    }
    
    
    // Create the object.
    let object = ARObject()
    object.vbo = device.newBufferWithBytes(
      vbo,
      length: sizeofValue(vbo[0]) * vbo.count,
      options: MTLResourceOptions()
    )
    object.indices = indices
    return object
  }
}

