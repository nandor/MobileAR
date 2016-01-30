// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import UIKit
import Metal

/**
 Renders the augmented scene.
 */
class ARSceneRenderer : ARRenderer {

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
  private var fboDepthStencil: MTLTexture!
  private var fboNormal: MTLTexture!
  private var fboMaterial: MTLTexture!
  private var fboSSAO: MTLTexture!

  // Data to render the quad spanning the entire screen.
  private var quadForeground: MTLDepthStencilState!
  private var quadBackground: MTLDepthStencilState!
  private var quadVBO: MTLBuffer!

  // Shader to render the background.
  private var backgroundRenderState: MTLRenderPipelineState!
  private var backgroundTexture: MTLTexture!

  // Shader to apply phong shaders.
  private var lightingRenderState: MTLRenderPipelineState!
  private var lightBuffer: MTLBuffer!

  // Shader to compute ambient occlusion.
  private var ssaoRenderState: MTLRenderPipelineState!
  private var ssaoRandomBuffer: MTLBuffer!
  private var ssaoSampleBuffer: MTLBuffer!

  // Object render state.
  private var objectDepthState: MTLDepthStencilState!
  private var objectRenderState: MTLRenderPipelineState!
  private var objectCache: [ARObject] = []


  // Background queue for loading data.
  private let backgroundQueue = dispatch_queue_create(
      "uk.ac.ic.MobileAR.ARSceneRenderer",
      DISPATCH_QUEUE_CONCURRENT
  )

  /**
   Initializes the renderer.
   */
  override init(view: UIView) throws {
    try super.init(view: view)

    // Set up the depth state.
    let quadBackgroundDesc = MTLDepthStencilDescriptor()
    quadBackgroundDesc.depthCompareFunction = .Always
    quadBackgroundDesc.depthWriteEnabled = false
    quadBackgroundDesc.frontFaceStencil.stencilCompareFunction = .NotEqual
    quadBackgroundDesc.frontFaceStencil.stencilFailureOperation = .Keep
    quadBackgroundDesc.frontFaceStencil.depthFailureOperation = .Keep
    quadBackgroundDesc.frontFaceStencil.depthStencilPassOperation = .Keep
    quadBackgroundDesc.frontFaceStencil.readMask = 0xFF
    quadBackgroundDesc.frontFaceStencil.writeMask = 0x00
    quadBackground = device.newDepthStencilStateWithDescriptor(quadBackgroundDesc)

    let quadForegroundDesc = MTLDepthStencilDescriptor()
    quadForegroundDesc.depthCompareFunction = .Always
    quadForegroundDesc.depthWriteEnabled = false
    quadForegroundDesc.frontFaceStencil.stencilCompareFunction = .Equal
    quadForegroundDesc.frontFaceStencil.stencilFailureOperation = .Keep
    quadForegroundDesc.frontFaceStencil.depthFailureOperation = .Keep
    quadForegroundDesc.frontFaceStencil.depthStencilPassOperation = .Keep
    quadForegroundDesc.frontFaceStencil.readMask = 0xFF
    quadForegroundDesc.frontFaceStencil.writeMask = 0x00
    quadForeground = device.newDepthStencilStateWithDescriptor(quadForegroundDesc)

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

    dispatch_async(backgroundQueue) {
      do {
        if (true) {
          self.objectCache = [ARObject.loadCube(self.device)]
        } else {
          let url = NSBundle.mainBundle().URLForResource("bunny", withExtension: "obj")
          self.objectCache = [try ARObject.loadObject(self.device, url: url!)]
        }
      } catch {
        print("\(error)")
      }
    }

    try setupGeometryBuffer()
    try setupFXPrograms()
    try setupLightSources()
    try setupSSAOBuffers()
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
    geomEncoder.setVertexBuffer(paramBuffer, offset: 0, atIndex: 1)
    for object in objectCache {
      geomEncoder.setVertexBuffer(object.vbo, offset: 0, atIndex: 0)
      if let ibo = object.ibo {
        geomEncoder.drawIndexedPrimitives(
            .Triangle,
            indexCount: object.indices,
            indexType: .UInt32,
            indexBuffer: ibo,
            indexBufferOffset: 0
        )
      } else {
        geomEncoder.drawPrimitives(
            .Triangle,
            vertexStart: 0,
            vertexCount: object.indices
        )
      }
    }

    geomEncoder.endEncoding()

    // Compute Screen Space Ambient Occlusion.
    // This pass is very expensive due to the fact that it reads a large amount
    // of data from textures and buffers from random locations. It requires a
    // separate pass since it writes to the AO texture.
    let ssaoPass = MTLRenderPassDescriptor()
    ssaoPass.colorAttachments[0].texture = fboSSAO
    ssaoPass.colorAttachments[0].loadAction = .DontCare
    ssaoPass.colorAttachments[0].storeAction = .Store

    ssaoPass.depthAttachment.loadAction = .Load
    ssaoPass.depthAttachment.storeAction = .DontCare
    ssaoPass.depthAttachment.texture = fboDepthStencil

    ssaoPass.stencilAttachment.loadAction = .Load
    ssaoPass.stencilAttachment.storeAction = .DontCare
    ssaoPass.stencilAttachment.texture = fboDepthStencil

    let ssaoEncoder = buffer.renderCommandEncoderWithDescriptor(ssaoPass)

    ssaoEncoder.setCullMode(.Back)
    ssaoEncoder.setStencilReferenceValue(0xFF)
    ssaoEncoder.setDepthStencilState(quadForeground)
    ssaoEncoder.setRenderPipelineState(ssaoRenderState)
    ssaoEncoder.setVertexBuffer(quadVBO, offset: 0, atIndex: 0)
    ssaoEncoder.setFragmentBuffer(paramBuffer, offset: 0, atIndex: 0)
    ssaoEncoder.setFragmentBuffer(ssaoSampleBuffer, offset: 0, atIndex: 1)
    ssaoEncoder.setFragmentBuffer(ssaoRandomBuffer, offset: 0, atIndex: 2)
    ssaoEncoder.setFragmentTexture(fboDepthStencil, atIndex: 0)
    ssaoEncoder.setFragmentTexture(fboNormal, atIndex: 0)
    ssaoEncoder.drawPrimitives(.Triangle, vertexStart: 0, vertexCount: 6)

    ssaoEncoder.endEncoding()

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
    fxEncoder.setDepthStencilState(quadBackground)
    fxEncoder.setRenderPipelineState(backgroundRenderState)
    fxEncoder.setVertexBuffer(quadVBO, offset: 0, atIndex: 0)
    fxEncoder.setFragmentTexture(backgroundTexture, atIndex: 0)
    fxEncoder.drawPrimitives(.Triangle, vertexStart: 0, vertexCount: 6)

    // Apply all the light sources.
    // Ligh sources are batched in groups of 32 and only those pixels are shaded
    // which belong to an object that was rendered previously.
    fxEncoder.setCullMode(.Back)
    fxEncoder.setStencilReferenceValue(0xFF)
    fxEncoder.setDepthStencilState(quadForeground)
    fxEncoder.setRenderPipelineState(lightingRenderState)
    fxEncoder.setVertexBuffer(quadVBO, offset: 0, atIndex: 0)
    fxEncoder.setFragmentBuffer(paramBuffer, offset: 0, atIndex: 0)
    fxEncoder.setFragmentBuffer(lightBuffer, offset: 0, atIndex: 1)
    fxEncoder.setFragmentTexture(fboDepthStencil, atIndex: 0)
    fxEncoder.setFragmentTexture(fboNormal, atIndex: 1)
    fxEncoder.setFragmentTexture(fboMaterial, atIndex: 2)
    fxEncoder.setFragmentTexture(fboSSAO, atIndex: 3)
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
    let fboSSAODesc = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
      .R32Float,
      width: width,
      height: height,
      mipmapped: false
    )
    fboSSAO = device.newTextureWithDescriptor(fboSSAODesc)
    fboSSAO.label = "FBOAO"
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
    // Blending is enabled to accumulate contributions from multiple light sources.
    guard let lighting = library.newFunctionWithName("lighting") else {
      throw ARRendererError.MissingFunction
    }
    let lightingRenderStateDesc = MTLRenderPipelineDescriptor()
    lightingRenderStateDesc.sampleCount = 1
    lightingRenderStateDesc.vertexFunction = fullscreen
    lightingRenderStateDesc.fragmentFunction = lighting
    lightingRenderStateDesc.colorAttachments[0].pixelFormat = .BGRA8Unorm

    lightingRenderStateDesc.colorAttachments[0].blendingEnabled = true
    lightingRenderStateDesc.colorAttachments[0].rgbBlendOperation = .Add
    lightingRenderStateDesc.colorAttachments[0].sourceRGBBlendFactor = .One
    lightingRenderStateDesc.colorAttachments[0].destinationRGBBlendFactor = .One
    lightingRenderStateDesc.colorAttachments[0].alphaBlendOperation = .Add
    lightingRenderStateDesc.colorAttachments[0].sourceAlphaBlendFactor = .One
    lightingRenderStateDesc.colorAttachments[0].destinationAlphaBlendFactor = .One

    lightingRenderStateDesc.stencilAttachmentPixelFormat = .Depth32Float_Stencil8
    lightingRenderStateDesc.depthAttachmentPixelFormat = .Depth32Float_Stencil8
    lightingRenderState = try device.newRenderPipelineStateWithDescriptor(lightingRenderStateDesc)

    // Fragment shader to perform SSAO.
    guard let ssao = library.newFunctionWithName("ssao") else {
      throw ARRendererError.MissingFunction
    }
    let ssaoRenderDesc = MTLRenderPipelineDescriptor()
    ssaoRenderDesc.sampleCount = 1
    ssaoRenderDesc.vertexFunction = fullscreen
    ssaoRenderDesc.fragmentFunction = ssao
    ssaoRenderDesc.colorAttachments[0].pixelFormat = .R32Float
    ssaoRenderDesc.stencilAttachmentPixelFormat = .Depth32Float_Stencil8
    ssaoRenderDesc.depthAttachmentPixelFormat = .Depth32Float_Stencil8
    ssaoRenderState = try device.newRenderPipelineStateWithDescriptor(ssaoRenderDesc)

  }

  /**
   Initializes all light sources.
   */
  private func setupLightSources() throws {
    var lightData = [Float](count: 16 * 32, repeatedValue: 0.0)

    lightData[0] = -1.0;
    lightData[1] = -0.5;
    lightData[2] = -1.0;
    lightData[3] = 0.0;

    lightData[4] = 0.2;
    lightData[5] = 0.2;
    lightData[6] = 0.2;
    lightData[7] = 0.0;

    lightData[8] = 0.7;
    lightData[9] = 0.7;
    lightData[10] = 0.7;
    lightData[11] = 0.0;

    lightData[12] = 1.0;
    lightData[13] = 1.0;
    lightData[14] = 1.0;
    lightData[15] = 1.0;

    lightBuffer = device.newBufferWithBytes(
      lightData,
      length: sizeofValue(lightData[0]) * lightData.count,
      options: MTLResourceOptions()
    )
    lightBuffer.label = "VBOLightSources"
  }

  /**
   Sets up SSAO.
   */
  private func setupSSAOBuffers() throws {

    var ssaoSampleData: [float4] = [float4(0.0, 0.0, 0.0, 0.0)]
    ssaoSampleBuffer = device.newBufferWithBytes(
      ssaoSampleData,
      length: sizeofValue(ssaoSampleData[0]) * ssaoSampleData.count,
      options: MTLResourceOptions()
    )
    ssaoSampleBuffer.label = "VBOSSAOSampleBuffer"

    var ssaoRandomData: [float4] = [float4(0.0, 0.0, 0.0, 0.0)]
    ssaoRandomBuffer = device.newBufferWithBytes(
      ssaoRandomData,
      length: sizeofValue(ssaoRandomData[0]) * ssaoRandomData.count,
      options: MTLResourceOptions()
    )
    ssaoRandomBuffer.label = "VBOSSSAORandomBuffer"
  }
}
