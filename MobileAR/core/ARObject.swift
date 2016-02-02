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
class ARObject {

  // Vertex Buffer Object.
  var vbo: MTLBuffer!
  // Number of indices.
  var indices: Int!
  // Index Buffer Object.
  var ibo: MTLBuffer?
  
  // Diffuse texture.
  var texDiffuse: MTLTexture!
  // Specular texture.
  var texSpecular: MTLTexture!
  // Bump map.
  var texNormal: MTLTexture!
  
  
  
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
      vbo[i * 8 + 7] = uv.y
    }
    
    // Create the object.
    let object = ARObject()
    object.vbo = device.newBufferWithBytes(
      vbo,
      length: sizeofValue(vbo[0]) * vbo.count,
      options: MTLResourceOptions()
    )
    object.indices = indices
    object.texDiffuse = try ARObject.loadTexture(device, url: url, type: "_diff", format: .BGRA8Unorm)
    object.texNormal = try ARObject.loadTexture(device, url: url, type: "_norm", format: .BGRA8Unorm)
    object.texSpecular = try ARObject.loadTexture(device, url: url, type: "_spec", format: .R8Unorm)
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

