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
  private var fboSSAOBlur: MTLTexture!

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
  private var ssaoBlurState: MTLRenderPipelineState!
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
    let quadBackgroundStencil = MTLStencilDescriptor()
    quadBackgroundStencil.stencilCompareFunction = .NotEqual
    quadBackgroundStencil.stencilFailureOperation = .Keep
    quadBackgroundStencil.depthFailureOperation = .Keep
    quadBackgroundStencil.depthStencilPassOperation = .Keep
    quadBackgroundStencil.readMask = 0xFF
    quadBackgroundStencil.writeMask = 0x00
    
    let quadBackgroundDesc = MTLDepthStencilDescriptor()
    quadBackgroundDesc.depthCompareFunction = .Always
    quadBackgroundDesc.depthWriteEnabled = false
    quadBackgroundDesc.frontFaceStencil = quadBackgroundStencil
    quadBackgroundDesc.backFaceStencil = quadBackgroundStencil
    quadBackground = device.newDepthStencilStateWithDescriptor(quadBackgroundDesc)

    let quadForegroundStencil = MTLStencilDescriptor()
    quadForegroundStencil.stencilCompareFunction = .Equal
    quadForegroundStencil.stencilFailureOperation = .Keep
    quadForegroundStencil.depthFailureOperation = .Keep
    quadForegroundStencil.depthStencilPassOperation = .Keep
    quadForegroundStencil.readMask = 0xFF
    quadForegroundStencil.writeMask = 0x00

    let quadForegroundDesc = MTLDepthStencilDescriptor()
    quadForegroundDesc.depthCompareFunction = .Always
    quadForegroundDesc.depthWriteEnabled = false
    quadForegroundDesc.frontFaceStencil = quadForegroundStencil
    quadForegroundDesc.backFaceStencil = quadForegroundStencil
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
    let objectStencil = MTLStencilDescriptor()
    objectStencil.depthStencilPassOperation = .Replace
    objectStencil.stencilCompareFunction = .Always
    objectStencil.stencilFailureOperation = .Keep
    objectStencil.depthFailureOperation = .Keep
    objectStencil.readMask = 0xFF
    objectStencil.writeMask = 0xFF

    let objectDepthDesc = MTLDepthStencilDescriptor()
    objectDepthDesc.depthCompareFunction = .LessEqual
    objectDepthDesc.depthWriteEnabled = true
    objectDepthDesc.frontFaceStencil = objectStencil
    objectDepthDesc.backFaceStencil = objectStencil
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
        self.objectCache = [try ARObject.loadObject(
            self.device,
            url: NSBundle.mainBundle().URLForResource("cup", withExtension: "obj")!
        )]
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
    geomPass.colorAttachments[1].loadAction = .DontCare
    geomPass.colorAttachments[1].storeAction = .Store

    geomPass.depthAttachment.loadAction = .Clear
    geomPass.depthAttachment.storeAction = .Store
    geomPass.depthAttachment.texture = fboDepthStencil
    geomPass.depthAttachment.clearDepth = 1.0

    geomPass.stencilAttachment.loadAction = .Clear
    geomPass.stencilAttachment.storeAction = .Store
    geomPass.stencilAttachment.texture = fboDepthStencil

    let geomEncoder = buffer.renderCommandEncoderWithDescriptor(geomPass)

    // Render the object.
    geomEncoder.setCullMode(.Front)
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
    ssaoPass.colorAttachments[0].loadAction = .Clear
    ssaoPass.colorAttachments[0].storeAction = .Store
    ssaoPass.colorAttachments[0].clearColor = MTLClearColorMake(1, 0, 0, 0)

    ssaoPass.depthAttachment.loadAction = .Load
    ssaoPass.depthAttachment.storeAction = .DontCare
    ssaoPass.depthAttachment.texture = fboDepthStencil

    ssaoPass.stencilAttachment.loadAction = .Load
    ssaoPass.stencilAttachment.storeAction = .DontCare
    ssaoPass.stencilAttachment.texture = fboDepthStencil

    let ssaoEncoder = buffer.renderCommandEncoderWithDescriptor(ssaoPass)

    ssaoEncoder.setStencilReferenceValue(0xFF)
    ssaoEncoder.setDepthStencilState(quadForeground)
    ssaoEncoder.setRenderPipelineState(ssaoRenderState)
    ssaoEncoder.setVertexBuffer(quadVBO, offset: 0, atIndex: 0)
    ssaoEncoder.setFragmentBuffer(paramBuffer, offset: 0, atIndex: 0)
    ssaoEncoder.setFragmentBuffer(ssaoSampleBuffer, offset: 0, atIndex: 1)
    ssaoEncoder.setFragmentBuffer(ssaoRandomBuffer, offset: 0, atIndex: 2)
    ssaoEncoder.setFragmentTexture(fboDepthStencil, atIndex: 0)
    ssaoEncoder.setFragmentTexture(fboNormal, atIndex: 1)
    ssaoEncoder.drawPrimitives(.Triangle, vertexStart: 0, vertexCount: 6)

    ssaoEncoder.endEncoding()

    // Blur the SSAO texture using a 4x4 box blur.
    let blurPass = MTLRenderPassDescriptor()
    blurPass.colorAttachments[0].texture = fboSSAOBlur
    blurPass.colorAttachments[0].loadAction = .DontCare
    blurPass.colorAttachments[0].storeAction = .Store

    let blurEncoder = buffer.renderCommandEncoderWithDescriptor(blurPass)

    blurEncoder.setDepthStencilState(quadForeground)
    blurEncoder.setRenderPipelineState(ssaoBlurState)
    blurEncoder.setVertexBuffer(quadVBO, offset: 0, atIndex: 0)
    blurEncoder.setFragmentTexture(fboSSAO, atIndex: 0)
    blurEncoder.drawPrimitives(.Triangle, vertexStart: 0, vertexCount: 6)

    blurEncoder.endEncoding()

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
    fxEncoder.setStencilReferenceValue(0xFF)
    fxEncoder.setDepthStencilState(quadBackground)
    fxEncoder.setRenderPipelineState(backgroundRenderState)
    fxEncoder.setVertexBuffer(quadVBO, offset: 0, atIndex: 0)
    fxEncoder.setFragmentTexture(backgroundTexture, atIndex: 0)
    fxEncoder.drawPrimitives(.Triangle, vertexStart: 0, vertexCount: 6)

    // Apply all the light sources.
    // Ligh sources are batched in groups of 32 and only those pixels are shaded
    // which belong to an object that was rendered previously.
    fxEncoder.setStencilReferenceValue(0xFF)
    fxEncoder.setDepthStencilState(quadForeground)
    fxEncoder.setRenderPipelineState(lightingRenderState)
    fxEncoder.setVertexBuffer(quadVBO, offset: 0, atIndex: 0)
    fxEncoder.setFragmentBuffer(paramBuffer, offset: 0, atIndex: 0)
    fxEncoder.setFragmentBuffer(lightBuffer, offset: 0, atIndex: 1)
    fxEncoder.setFragmentTexture(fboDepthStencil, atIndex: 0)
    fxEncoder.setFragmentTexture(fboNormal, atIndex: 1)
    fxEncoder.setFragmentTexture(fboMaterial, atIndex: 2)
    fxEncoder.setFragmentTexture(fboSSAOBlur, atIndex: 3)
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
    fboSSAOBlur = device.newTextureWithDescriptor(fboSSAODesc)
    fboSSAO.label = "FBOSSAOBlur"
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

    // Fragment shader to perform SSAO.
    guard let ssaoBlur = library.newFunctionWithName("ssaoBlur") else {
      throw ARRendererError.MissingFunction
    }
    let ssaoBlurDesc = MTLRenderPipelineDescriptor()
    ssaoBlurDesc.sampleCount = 1
    ssaoBlurDesc.vertexFunction = fullscreen
    ssaoBlurDesc.fragmentFunction = ssaoBlur
    ssaoBlurDesc.colorAttachments[0].pixelFormat = .R32Float
    ssaoBlurState = try device.newRenderPipelineStateWithDescriptor(ssaoBlurDesc)
  }

  /**
   Initializes all light sources.
   */
  private func setupLightSources() throws {
    var lightData = [Float](count: 16 * 32, repeatedValue: 0.0)

    lightData[0] = -1.0;
    lightData[1] = -1.0;
    lightData[2] = -1.0;
    lightData[3] = 0.0;

    lightData[4] = 0.4;
    lightData[5] = 0.4;
    lightData[6] = 0.4;
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

    // Set up a buffer with 32 sample vectors. The shader might choose to
    // use only a subset of these in order to increase performance.
    var ssaoSampleData: [float4] = [
        float4(-0.0222812286, -0.0097610634, 0.0190471473, 0.0),
        float4(-0.0550172494, -0.0309991154, 0.0676510781, 0.0),
        float4( 0.0326691691,  0.0334404281, 0.0380219642, 0.0),
        float4( 0.0437514486, -0.0102820787, 0.0337031351, 0.0),
        float4( 0.0019365485, -0.0044538348, 0.0312760117, 0.0),
        float4( 0.0566276267,  0.0503924542, 0.0531489421, 0.0),
        float4(-0.0014951475,  0.0024281197, 0.0173591884, 0.0),
        float4(-0.0164670202, -0.0578062973, 0.1123648725, 0.0),
        float4(-0.1000401022,  0.0311720643, 0.0920496615, 0.0),
        float4(-0.0438685685,  0.0715038973, 0.1083699433, 0.0),
        float4( 0.0149985533, -0.0170551220, 0.0185657416, 0.0),
        float4( 0.0354595464, -0.0363755173, 0.0323577105, 0.0),
        float4(-0.0203935451, -0.0745134646, 0.1541178105, 0.0),
        float4( 0.0028391215,  0.0116091792, 0.0576031406, 0.0),
        float4(-0.0196249165, -0.0478437599, 0.0425324788, 0.0),
        float4( 0.0729668184, -0.0522721479, 0.0875701738, 0.0),
        float4(-0.1532114786, -0.1522172360, 0.2735333576, 0.0),
        float4(-0.0298943708,  0.1737209567, 0.3183226437, 0.0),
        float4(-0.1656550946, -0.0719748123, 0.1968226893, 0.0),
        float4(-0.0095653149, -0.2941228294, 0.2039285730, 0.0),
        float4(-0.1331204501,  0.1220435809, 0.0964000304, 0.0),
        float4(-0.0403178220, -0.3809901890, 0.3414482621, 0.0),
        float4( 0.0882988347,  0.0455553367, 0.2918320574, 0.0),
        float4(-0.1175072503,  0.0388894681, 0.1550289903, 0.0),
        float4(-0.0533728880, -0.0381621740, 0.0610825723, 0.0),
        float4( 0.2468512030,  0.3388266965, 0.2949817385, 0.0),
        float4( 0.2449600832,  0.2042880967, 0.6010089206, 0.0),
        float4( 0.6424967231,  0.0443461169, 0.4040266177, 0.0),
        float4( 0.3099913096,  0.1985537725, 0.3454406527, 0.0),
        float4( 0.0754919457, -0.0634370161, 0.0774910082, 0.0),
        float4( 0.0531734967,  0.0233182866, 0.0956308795, 0.0),
        float4( 0.5550298510, -0.0702125778, 0.3265220542, 0.0),
    ]
    ssaoSampleBuffer = device.newBufferWithBytes(
      ssaoSampleData,
      length: sizeofValue(ssaoSampleData[0]) * ssaoSampleData.count,
      options: MTLResourceOptions()
    )
    ssaoSampleBuffer.label = "VBOSSAOSampleBuffer"

    // Set up a 4x4 texture with randomly selected vectors with x, y \in [0, 1].
    var ssaoRandomData: [float4] = [
      float4( 0.63618570,  0.51077760,  0.0, 0.0),
      float4( 0.50891661, -0.34688258,  0.0, 0.0),
      float4( 0.62890755, -0.45142945,  0.0, 0.0),
      float4(-0.34869557, -0.41754699,  0.0, 0.0),
      float4(-0.12747335, -0.67727395,  0.0, 0.0),
      float4( 0.84289647,  0.32273283,  0.0, 0.0),
      float4( 0.14654619,  0.67703445,  0.0, 0.0),
      float4(-0.88995941, -0.89987678,  0.0, 0.0),
      float4( 0.16366023,  0.43668146,  0.0, 0.0),
      float4( 0.37088478, -0.86388887,  0.0, 0.0),
      float4(-0.76671633,  0.12611534,  0.0, 0.0),
      float4(-0.51218073, -0.95123229,  0.0, 0.0),
      float4(-0.57194316, -0.16738459,  0.0, 0.0),
      float4(-0.89127350,  0.22852176,  0.0, 0.0),
      float4( 0.73067920,  0.43298104,  0.0, 0.0),
      float4(-0.41123954,  0.69549418,  0.0, 0.0),
    ]
    ssaoRandomBuffer = device.newBufferWithBytes(
      ssaoRandomData,
      length: sizeofValue(ssaoRandomData[0]) * ssaoRandomData.count,
      options: MTLResourceOptions()
    )
    ssaoRandomBuffer.label = "VBOSSSAORandomBuffer"
  }
}
