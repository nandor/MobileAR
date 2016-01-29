// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import UIKit
import Metal

/**
 Renders the augmented scene.
 */
class ARSceneRenderer : ARRenderer {

  // Data to render the quad spanning the entire screen.
  private var quadDepthStateInclude: MTLDepthStencilState!
  private var quadDepthStateExclude: MTLDepthStencilState!
  private var quadVBO: MTLBuffer!

  // Texture from the camera.
  private var backgroundTexture: MTLTexture!
  
  // FX shader states.
  private var backgroundRenderState: MTLRenderPipelineState!
  private var lightingRenderState: MTLRenderPipelineState!
  
  // Object render state.
  private var objectDepthState: MTLDepthStencilState!
  private var objectRenderState: MTLRenderPipelineState!
  private var objectCache: [ARObject] = []

  // Render targets. Data is encoded as:
  //
  // 0       8      16      24        32
  // +---------------------------------+
  // |              Depth              |
  // +---------------+-----------------+
  // |       nx      |        ny       |
  // +-------+-------+-------+---------+
  // |   ar  |  ag   |  ab   |  spec   |
  // +-------+-------+-------+---------+
  // |        ambient occlusion        |
  // +---------------------------------+
  //
  private var fboDepthStencil: MTLTexture!
  private var fboNormal: MTLTexture!
  private var fboMaterial: MTLTexture!
  private var fboAO: MTLTexture!
  
  /**
   Initializes the renderer.
   */
  override init(view: UIView) throws {
    try super.init(view: view)

    // Set up the depth state.
    let quadDepthExcludeDesc = MTLDepthStencilDescriptor()
    quadDepthExcludeDesc.depthCompareFunction = .Always
    quadDepthExcludeDesc.depthWriteEnabled = false
    quadDepthExcludeDesc.frontFaceStencil.stencilCompareFunction = .NotEqual
    quadDepthExcludeDesc.frontFaceStencil.stencilFailureOperation = .Keep
    quadDepthExcludeDesc.frontFaceStencil.depthFailureOperation = .Keep
    quadDepthExcludeDesc.frontFaceStencil.depthStencilPassOperation = .Keep
    quadDepthExcludeDesc.frontFaceStencil.readMask = 0xFF
    quadDepthExcludeDesc.frontFaceStencil.writeMask = 0x00
    quadDepthStateExclude = device.newDepthStencilStateWithDescriptor(quadDepthExcludeDesc)
    
    let quadDepthIncludeDesc = MTLDepthStencilDescriptor()
    quadDepthIncludeDesc.depthCompareFunction = .Always
    quadDepthIncludeDesc.depthWriteEnabled = false
    quadDepthIncludeDesc.frontFaceStencil.stencilCompareFunction = .Equal
    quadDepthIncludeDesc.frontFaceStencil.stencilFailureOperation = .Keep
    quadDepthIncludeDesc.frontFaceStencil.depthFailureOperation = .Keep
    quadDepthIncludeDesc.frontFaceStencil.depthStencilPassOperation = .Keep
    quadDepthIncludeDesc.frontFaceStencil.readMask = 0xFF
    quadDepthIncludeDesc.frontFaceStencil.writeMask = 0x00
    quadDepthStateInclude = device.newDepthStencilStateWithDescriptor(quadDepthIncludeDesc)

    // Initialize the VBO of the full-screen quad.
    var vbo : [Float] = [
      -1, -1,
      -1,  1,
       1,  1,
      -1, -1,
       1,  1,
       1, -1,
    ]
    quadVBO = device.newBufferWithBytes(
        vbo,
        length: sizeofValue(vbo[0]) * vbo.count,
        options: MTLResourceOptions()
    )
    quadVBO.label = "VBOQuad"

    // Create the background texture.
    let backgroundTextureDesc = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
        .BGRA8Unorm,
        width: Int(640),
        height: Int(360),
        mipmapped: false
    )
    backgroundTexture = device.newTextureWithDescriptor(backgroundTextureDesc)
    
    // Set up the depth state for objects.
    let objectDepthDesc = MTLDepthStencilDescriptor()
    objectDepthDesc.depthCompareFunction = .LessEqual
    objectDepthDesc.depthWriteEnabled = true
    objectDepthDesc.frontFaceStencil.depthStencilPassOperation = .Replace
    objectDepthDesc.frontFaceStencil.stencilCompareFunction = .Always
    objectDepthDesc.frontFaceStencil.stencilFailureOperation = .Keep
    objectDepthDesc.frontFaceStencil.depthFailureOperation = .Keep
    objectDepthDesc.frontFaceStencil.readMask = 0xFF
    objectDepthDesc.frontFaceStencil.writeMask = 0xFF
    objectDepthState = device.newDepthStencilStateWithDescriptor(objectDepthDesc)

    // Set up the shaders.
    guard let objectVert = library.newFunctionWithName("objectVert") else {
      throw ARRendererError.MissingFunction
    }
    guard let objectFrag = library.newFunctionWithName("objectFrag") else {
      throw ARRendererError.MissingFunction
    }

    // Create the pipeline descriptor.
    let objectRenderDesc = MTLRenderPipelineDescriptor()
    objectRenderDesc.sampleCount = 1
    objectRenderDesc.vertexFunction = objectVert
    objectRenderDesc.fragmentFunction = objectFrag
    objectRenderDesc.colorAttachments[0].pixelFormat = .RG16Float
    objectRenderDesc.colorAttachments[1].pixelFormat = .RGBA8Unorm
    objectRenderDesc.depthAttachmentPixelFormat = .Depth32Float_Stencil8
    objectRenderDesc.stencilAttachmentPixelFormat = .Depth32Float_Stencil8
    objectRenderState = try device.newRenderPipelineStateWithDescriptor(objectRenderDesc)

    objectCache.append(ARObject(device: device))
    
    try setupGeometryBuffer()
    try setupFXPrograms()
  }

  /**
   Updates the camera texture.
   */
  func updateFrame(frame: UIImage) {
    frame.toMTLTexture(backgroundTexture)
  }
  
  /**
   Renders a single frame.
   */
  override func onRenderFrame(target: MTLTexture, buffer: MTLCommandBuffer) {
    
    // Start the pass to render to the geometry buffer.
    let geomPass = MTLRenderPassDescriptor()
    
    geomPass.colorAttachments[0].texture = fboNormal
    geomPass.colorAttachments[0].loadAction = .DontCare
    geomPass.colorAttachments[0].storeAction = .Store
    
    geomPass.colorAttachments[1].texture = fboMaterial
    geomPass.colorAttachments[1].loadAction = .Clear
    geomPass.colorAttachments[1].storeAction = .Store
    
    geomPass.depthAttachment.loadAction = .Clear
    geomPass.depthAttachment.storeAction = .Store
    geomPass.depthAttachment.texture = fboDepthStencil
    
    geomPass.stencilAttachment.loadAction = .Clear
    geomPass.stencilAttachment.storeAction = .Store
    geomPass.stencilAttachment.texture = fboDepthStencil
    
    let geomEncoder = buffer.renderCommandEncoderWithDescriptor(geomPass)

    // Render the object.
    geomEncoder.setCullMode(.Back)
    geomEncoder.setStencilReferenceValue(0xFF)
    geomEncoder.setDepthStencilState(objectDepthState)
    geomEncoder.setRenderPipelineState(objectRenderState)
    geomEncoder.setVertexBuffer(objectCache[0].vbo, offset: 0, atIndex: 0)
    geomEncoder.setVertexBuffer(params, offset: 0, atIndex: 1)
    geomEncoder.drawIndexedPrimitives(
        .Triangle,
        indexCount: objectCache[0].indices,
        indexType: .UInt32,
        indexBuffer: objectCache[0].ibo,
        indexBufferOffset: 0
    )
    
    geomEncoder.endEncoding()

    // Set up post-processing.
    let fxPass = MTLRenderPassDescriptor()
    
    fxPass.colorAttachments[0].texture = target
    fxPass.colorAttachments[0].loadAction = .DontCare
    fxPass.colorAttachments[0].storeAction = .Store
    
    fxPass.depthAttachment.loadAction = .Load
    fxPass.depthAttachment.storeAction = .DontCare
    fxPass.depthAttachment.texture = fboDepthStencil
    
    fxPass.stencilAttachment.loadAction = .Load
    fxPass.stencilAttachment.storeAction = .DontCare
    fxPass.stencilAttachment.texture = fboDepthStencil
    
    let fxEncoder = buffer.renderCommandEncoderWithDescriptor(fxPass)
    
    // Draw the background texture.
    // In order to reduce the amount of pixels highlighted by the background
    // texture, stencil testing is used to discard those regions which are
    // occluded by objects rendered on top of the scene.
    fxEncoder.setCullMode(.Back)
    fxEncoder.setStencilReferenceValue(0xFF)
    fxEncoder.setDepthStencilState(quadDepthStateExclude)
    fxEncoder.setRenderPipelineState(backgroundRenderState)
    fxEncoder.setVertexBuffer(quadVBO, offset: 0, atIndex: 0)
    fxEncoder.setFragmentTexture(backgroundTexture, atIndex: 0)
    fxEncoder.drawPrimitives(.Triangle, vertexStart: 0, vertexCount: 6)
    
    // Apply all the light sources.
    // Ligh sources are batched in groups of 32 and only those pixels are shaded
    // which belong to an object that was rendered previously.
    fxEncoder.setCullMode(.Back)
    fxEncoder.setStencilReferenceValue(0xFF)
    fxEncoder.setDepthStencilState(quadDepthStateInclude)
    fxEncoder.setRenderPipelineState(lightingRenderState)
    fxEncoder.setVertexBuffer(quadVBO, offset: 0, atIndex: 0)
    fxEncoder.setVertexBuffer(params, offset: 0, atIndex: 1)
    fxEncoder.setFragmentTexture(fboDepthStencil, atIndex: 0)
    fxEncoder.setFragmentTexture(fboNormal, atIndex: 1)
    fxEncoder.setFragmentTexture(fboMaterial, atIndex: 2)
    fxEncoder.setFragmentTexture(fboAO, atIndex: 3)
    fxEncoder.drawPrimitives(.Triangle, vertexStart: 0, vertexCount: 6)
    
    fxEncoder.endEncoding()
  }
  
  
  /**
   Initializes all textures for the geometry buffer.
   */
  private func setupGeometryBuffer() throws {
    
    // Depth and stencil must be combined.
    let fboDepthStencilDesc = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
      .Depth32Float_Stencil8,
      width: width,
      height: height,
      mipmapped: false
    )
    fboDepthStencil = device.newTextureWithDescriptor(fboDepthStencilDesc)
    fboDepthStencil.label = "FBODepthStencil"
    
    // Two channels store the x and y components of a normal vector.
    let fboNormalDesc = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
      .RG16Float,
      width: width,
      height: height,
      mipmapped: false
    )
    fboNormal = device.newTextureWithDescriptor(fboNormalDesc)
    fboNormal.label = "FBONormal"
    
    // Materials store albedo r, g and b, as well as a specular factor.
    let fboMaterialDesc = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
      .RGBA8Unorm,
      width: width,
      height: height,
      mipmapped: false
    )
    fboMaterial = device.newTextureWithDescriptor(fboMaterialDesc)
    fboMaterial.label = "FBOMaterial"
    
    // The AO texture stores vertex positions.
    let fboAODesc = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
      .R32Float,
      width: width,
      height: height,
      mipmapped: false
    )
    fboAO = device.newTextureWithDescriptor(fboAODesc)
    fboAO.label = "FBOAO"
  }
  
  /**
   Initializes all FX programs.
   */
  private func setupFXPrograms() throws {
    
    // The vertex shader will simply render a full-screen quad.
    guard let fullscreen = library.newFunctionWithName("fullscreen") else {
      throw ARRendererError.MissingFunction
    }
    
    // Fragment shader to render the background texture.
    guard let background = library.newFunctionWithName("background") else {
      throw ARRendererError.MissingFunction
    }
    let backgroundRenderDesc = MTLRenderPipelineDescriptor()
    backgroundRenderDesc.sampleCount = 1
    backgroundRenderDesc.vertexFunction = fullscreen
    backgroundRenderDesc.fragmentFunction = background
    backgroundRenderDesc.colorAttachments[0].pixelFormat = .BGRA8Unorm
    backgroundRenderDesc.stencilAttachmentPixelFormat = .Depth32Float_Stencil8
    backgroundRenderDesc.depthAttachmentPixelFormat = .Depth32Float_Stencil8
    backgroundRenderState = try device.newRenderPipelineStateWithDescriptor(backgroundRenderDesc)
    
    // Fragment shader to apply lighting.
    guard let lighting = library.newFunctionWithName("lighting") else {
      throw ARRendererError.MissingFunction
    }
    let lightingRenderStateDesc = MTLRenderPipelineDescriptor()
    lightingRenderStateDesc.sampleCount = 1
    lightingRenderStateDesc.vertexFunction = fullscreen
    lightingRenderStateDesc.fragmentFunction = lighting
    lightingRenderStateDesc.colorAttachments[0].pixelFormat = .BGRA8Unorm
    lightingRenderStateDesc.stencilAttachmentPixelFormat = .Depth32Float_Stencil8
    lightingRenderStateDesc.depthAttachmentPixelFormat = .Depth32Float_Stencil8
    lightingRenderState = try device.newRenderPipelineStateWithDescriptor(lightingRenderStateDesc)
  }
}
