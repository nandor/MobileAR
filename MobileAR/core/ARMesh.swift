// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import Foundation
import simd

enum ARObjectError : ErrorType {
  case InvalidToken
  case InvalidPath
  case MissingTexture
}


/**
 Object that can be rendered, holds an IBO and a VBO.
 */
class ARMesh {

  // Vertex Buffer Object.
  var vbo: MTLBuffer!
  // Number of indices.
  var indices: Int!
  
  // Diffuse texture.
  var texDiffuse: MTLTexture!
  // Specular texture.
  var texSpecular: MTLTexture!
  // Bump map.
  var texNormal: MTLTexture!
  
  
  
  /**
   Loads an object from a Wavefront OBJ file.
   */
  static func loadObject(device: MTLDevice, url: NSURL) throws -> ARMesh {
    
    var vv: [float3] = []
    var vn: [float3] = []
    var vt: [float2] = []
    var idx: [Int] = []
    
    // Read the data file.
    for line in try ARFileReader(url: url) {
      let t = line.componentsSeparatedByString(" ")
      switch (t[0]) {
        case "f":
          for i in 1...3 {
            let verts = t[i].componentsSeparatedByString("/")
            idx.append(Int(verts[0])! - 1)
            idx.append(Int(verts[1])! - 1)
            idx.append(Int(verts[2])! - 1)
          }
        case "v":
          vv.append(float3(Float(t[1])!, Float(t[2])!, Float(t[3])!))
        case "vn":
          vn.append(float3(Float(t[1])!, Float(t[2])!, Float(t[3])!))
        case "vt":
          vt.append(float2(Float(t[1])!, Float(t[2])!))
        case "#", "s":
          continue
        default:
          throw ARObjectError.InvalidToken
      }
    }
    
    // Build the vertex buffer.
    let indices = idx.count / 3
    var vbo = [Float](count: indices * 16, repeatedValue: 0.0)
    for var i = 0; i < indices; i += 3 {
      let v0 = vv[idx[(i + 0) * 3 + 0]]
      let v1 = vv[idx[(i + 1) * 3 + 0]]
      let v2 = vv[idx[(i + 2) * 3 + 0]]
      let t0 = vt[idx[(i + 0) * 3 + 1]]
      let t1 = vt[idx[(i + 1) * 3 + 1]]
      let t2 = vt[idx[(i + 2) * 3 + 1]]
      
      let ve0 = v1 - v0, ve1 = v2 - v0
      let te0 = t1 - t0, te1 = t2 - t0
      
      let f = 1.0 / (te0.x * te1.y - te0.y * te1.x)
      let t = f * (te1.y * ve0 - te0.y * ve1)
      let b = f * (te0.x * ve1 - te1.x * ve0)
      
      vbo[(i + 0) * 16 +  0] = v0.x
      vbo[(i + 0) * 16 +  1] = v0.y
      vbo[(i + 0) * 16 +  2] = v0.z
      vbo[(i + 0) * 16 +  6] = t0.x
      vbo[(i + 0) * 16 +  7] = t0.y
      
      vbo[(i + 1) * 16 +  0] = v1.x
      vbo[(i + 1) * 16 +  1] = v1.y
      vbo[(i + 1) * 16 +  2] = v1.z
      vbo[(i + 1) * 16 +  6] = t1.x
      vbo[(i + 1) * 16 +  7] = t1.y
      
      vbo[(i + 2) * 16 +  0] = v2.x
      vbo[(i + 2) * 16 +  1] = v2.y
      vbo[(i + 2) * 16 +  2] = v2.z
      vbo[(i + 2) * 16 +  6] = t2.x
      vbo[(i + 2) * 16 +  7] = t2.y
      
      for var j = 0, k = i; j < 3; j += 1, k += 1 {
        let norm = vn[idx[k * 3 + 2]]
        
        vbo[k * 16 +  3] = norm.x
        vbo[k * 16 +  4] = norm.y
        vbo[k * 16 +  5] = norm.z
        vbo[k * 16 +  8] = t.x
        vbo[k * 16 +  9] = t.y
        vbo[k * 16 + 10] = t.z
        vbo[k * 16 + 11] = b.x
        vbo[k * 16 + 12] = b.y
        vbo[k * 16 + 13] = b.z
      }
    }
    
    // Create the object.
    let object = ARMesh()
    object.vbo = device.newBufferWithBytes(
      vbo,
      length: sizeofValue(vbo[0]) * vbo.count,
      options: MTLResourceOptions()
    )
    object.indices = indices
    object.texDiffuse = try ARMesh.loadTexture(device, url: url, type: "_diff", format: .BGRA8Unorm)
    object.texNormal = try ARMesh.loadTexture(device, url: url, type: "_norm", format: .BGRA8Unorm)
    object.texSpecular = try ARMesh.loadTexture(device, url: url, type: "_spec", format: .R8Unorm)
    return object
  }
  
  /**
   Loads a texture map.
   */
  static private func loadTexture(
      device: MTLDevice,
      url: NSURL,
      type: String,
      format: MTLPixelFormat) throws
      -> MTLTexture
  {
    guard let name = (url.lastPathComponent as NSString?)?.stringByDeletingPathExtension else {
      throw ARObjectError.InvalidPath
    }
    guard let dir = url.URLByDeletingLastPathComponent else {
      throw ARObjectError.InvalidPath
    }
    
    let path = dir.URLByAppendingPathComponent(name + type + ".png")
    guard let image = UIImage(contentsOfFile: path.path!) else {
      throw ARObjectError.MissingTexture
    }
    
    let texDesc = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
      format,
      width: Int(image.size.width),
      height: Int(image.size.height),
      mipmapped: false
    )
    
    let texture = device.newTextureWithDescriptor(texDesc)
    image.toMTLTexture(texture);
    return texture
  }
}

