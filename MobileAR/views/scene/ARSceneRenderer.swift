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
  // |       AO      |      envmap     |
  // +---------------------------------+
  private var fboDepthStencil: MTLTexture!
  private var fboNormal: MTLTexture!
  private var fboMaterial: MTLTexture!
  private var fboSSAOEnv: MTLTexture!
  private var fboSSAOBlurEnv: MTLTexture!

  // Data to render the quad spanning the entire screen.
  private var quadLE: MTLDepthStencilState!
  private var quadGE: MTLDepthStencilState!
  private var quadVBO: MTLBuffer!

  // Shader to render the background.
  private var backgroundRenderState: MTLRenderPipelineState!
  private var backgroundTexture: MTLTexture!

  // Shader to apply phong shaders.
  private var lightingRenderState: MTLRenderPipelineState!

  // Shader to compute ambient occlusion.
  private var ssaoRenderState: MTLRenderPipelineState!
  private var ssaoBlurState: MTLRenderPipelineState!
  private var ssaoRandomBuffer: MTLBuffer!
  private var ssaoSampleBuffer: MTLBuffer!

  // Object render state.
  private var objectDepthState: MTLDepthStencilState!
  private var objectRenderState: MTLRenderPipelineState!
  
  // Pedestal rendered under objects for AO.
  private var pedestalDepthState: MTLDepthStencilState!
  private var pedestalRenderState: MTLRenderPipelineState!
  private var pedestalBuffer: MTLBuffer!

  // Background queue for loading data.
  private let backgroundQueue = dispatch_queue_create(
      "uk.ac.ic.MobileAR.ARSceneRenderer",
      DISPATCH_QUEUE_CONCURRENT
  )
  
  // Environment map texture.
  private var envMap: MTLTexture!
  
  // Object cache.
  private var meshes: [String: ARMesh?] = [String: ARMesh?]()
  
  // Information about a single light source.
  private struct Light {
    var direction: float4
    var ambient: float4
    var diffuse: float4
    var specular: float4
  }
  
  // Number of light sources to render in a batch.
  private let kLightBatch = 32
  // Number of objects to render in an instance batch.
  private let kInstanceBatch = 4
  
  // Objects to be rendered.
  internal var objects: [ARObject] = []
  // Light sources to be used.
  internal var lights: [ARLight] = []
  
  
  /**
   Initializes the renderer.
   */
  init(view: UIView, environment: AREnvironment) throws {
    try super.init(view: view)
    
    self.lights = environment.lights
    
    try setupObject()
    try setupGeometryBuffer()
    try setupFXPrograms()
    try setupSSAOBuffers()
    try setupPedestal()
    try setupEnvironmentMap(environment.map)
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
    renderGeometry(target, buffer: buffer)
    renderPedestals(target, buffer: buffer)
    renderSSAO(target, buffer: buffer)
    renderSSAOBlur(target, buffer: buffer)
    renderBackground(target, buffer: buffer)
    renderLights(target, buffer: buffer)
  }
  
  /**
   Pass to render to the geometry buffer.
    
   This pass renders all objects and writes to the depth buffer, sets
   all pixels to 0xFF in the stencil buffer, writes the albedo + specular
   exponent to the material buffer and saves the X and Y components of the
   normalized normal vectors into the normal buffer.
   */
  private func renderGeometry(target: MTLTexture, buffer: MTLCommandBuffer) {
    
    let geomPass = MTLRenderPassDescriptor()
    geomPass.colorAttachments[0].texture = fboNormal
    geomPass.colorAttachments[0].loadAction = .DontCare
    geomPass.colorAttachments[0].storeAction = .Store
    geomPass.colorAttachments[1].texture = fboMaterial
    geomPass.colorAttachments[1].loadAction = .DontCare
    geomPass.colorAttachments[1].storeAction = .Store
    geomPass.colorAttachments[2].texture = fboSSAOEnv
    geomPass.colorAttachments[2].loadAction = .Clear
    geomPass.colorAttachments[2].storeAction = .Store
    geomPass.colorAttachments[2].clearColor = MTLClearColorMake(1, 0, 0, 0)
    geomPass.depthAttachment.loadAction = .Clear
    geomPass.depthAttachment.storeAction = .Store
    geomPass.depthAttachment.texture = fboDepthStencil
    geomPass.depthAttachment.clearDepth = 1.0
    geomPass.stencilAttachment.loadAction = .Clear
    geomPass.stencilAttachment.storeAction = .Store
    geomPass.stencilAttachment.texture = fboDepthStencil
    
    let geomEncoder = buffer.renderCommandEncoderWithDescriptor(geomPass)
    geomEncoder.label = "Geometry"
    geomEncoder.setCullMode(.Front)
    geomEncoder.setStencilReferenceValue(0xFF)
    geomEncoder.setDepthStencilState(objectDepthState)
    geomEncoder.setRenderPipelineState(objectRenderState)
    
    var groups = [String: [float4x4]]()
    for object in objects {
      if var group = groups[object.mesh] {
        group.append(object.model)
        groups[object.mesh] = group
      } else {
        groups[object.mesh] = [object.model]
      }
    }
    
    for (name, mats) in groups {
      switch meshes[name] {
        case .None:
          // If the object was not encountered already, queue loading it.
          self.meshes[name] = nil
          dispatch_async(backgroundQueue) {
            self.meshes[name] = try? ARMesh.loadObject(
                self.device,
                url: NSBundle.mainBundle().URLForResource(
                    name,
                    withExtension: "obj"
                )!
            )
          }

        case .Some(.None):
          // If the object is being loaded, skip.
          continue

        case .Some(.Some(let mesh)):
          // Prepare common attributes.
          geomEncoder.setVertexBuffer(mesh.vbo, offset: 0, atIndex: 0)
          geomEncoder.setVertexBuffer(paramBuffer, offset: 0, atIndex: 1)
          geomEncoder.setFragmentTexture(mesh.texDiffuse, atIndex: 0)
          geomEncoder.setFragmentTexture(mesh.texSpecular, atIndex: 1)
          geomEncoder.setFragmentTexture(mesh.texNormal, atIndex: 2)
          
          for var batch = 0; batch < mats.count; batch += kInstanceBatch {
            
            // Create a temporary buffer to store object parameters.
            let modelBuffer = device.newBufferWithLength(
              sizeof(ARObjectParameters) * kInstanceBatch,
              options: MTLResourceOptions()
            )
            
            // Fill in the buffer with model matrices.
            var data = UnsafeMutablePointer<ARObjectParameters>(modelBuffer.contents())
            let size = min(kInstanceBatch, mats.count - batch)
            for var i = 0; i < size; ++i {
              let model = mats[batch + i]
              data.memory.model = model
              data.memory.invModel = model.inverse
              data.memory.normModel = model.inverse.transpose
              data = data.successor()
            }
            
            // If the mesh was loaded, render it.
            geomEncoder.setVertexBuffer(modelBuffer, offset: 0, atIndex: 2)
            geomEncoder.drawPrimitives(
                .Triangle,
                vertexStart: 0,
                vertexCount: mesh.indices,
                instanceCount: size
            )
          }
      }
    }
    geomEncoder.endEncoding()
  }
  
  /** 
   Pass to render a rectangle under each object into the depth buffer.
   
   Also and to decrement values in the stencil buffer. This "pedestal" is used
   to add some slight shade under each object during the SSAO pass. Data is
   not written to the material buffer and the stencil buffer is set to 0xF0
   in order to distinguish this plane from actual objects. The background
   image will be modulated using AO, however lighting should not be applied.
   */
  private func renderPedestals(target: MTLTexture, buffer: MTLCommandBuffer) {
    let pedestalPass = MTLRenderPassDescriptor()
    pedestalPass.colorAttachments[0].loadAction = .Load
    pedestalPass.colorAttachments[0].storeAction = .Store
    pedestalPass.colorAttachments[0].texture = fboNormal
    pedestalPass.depthAttachment.loadAction = .Load
    pedestalPass.depthAttachment.storeAction = .Store
    pedestalPass.depthAttachment.texture = fboDepthStencil
    pedestalPass.stencilAttachment.loadAction = .Load
    pedestalPass.stencilAttachment.storeAction = .Store
    pedestalPass.stencilAttachment.texture = fboDepthStencil
    
    let pedestalEncoder = buffer.renderCommandEncoderWithDescriptor(pedestalPass)
    pedestalEncoder.label = "Pedestal"
    pedestalEncoder.setCullMode(.Front)
    pedestalEncoder.setStencilReferenceValue(0xF0)
    pedestalEncoder.setDepthStencilState(pedestalDepthState)
    pedestalEncoder.setRenderPipelineState(pedestalRenderState)
    pedestalEncoder.setVertexBuffer(pedestalBuffer, offset: 0, atIndex: 0)
    pedestalEncoder.setVertexBuffer(paramBuffer, offset: 0, atIndex: 1)
    
    for var batch = 0; batch < objects.count; batch += kInstanceBatch {
      
      // Create a temporary buffer to store object parameters.
      let modelBuffer = device.newBufferWithLength(
        sizeof(ARObjectParameters) * kInstanceBatch,
        options: MTLResourceOptions()
      )
      
      // Fill in the buffer with model matrices.
      var data = UnsafeMutablePointer<ARObjectParameters>(modelBuffer.contents())
      let size = min(kInstanceBatch, objects.count - batch)
      for var i = 0; i < size; ++i {
        let model = objects[batch + i].model
        data.memory.model = model
        data.memory.invModel = model.inverse
        data.memory.normModel = model.inverse.transpose
        data = data.successor()
      }
      
      pedestalEncoder.setVertexBuffer(modelBuffer, offset: 0, atIndex: 2)
      for _ in objects {
        pedestalEncoder.drawPrimitives(
            .Triangle,
            vertexStart: 0,
            vertexCount: 6,
            instanceCount: size
        )
      }
    }
    pedestalEncoder.endEncoding()
  }
  
  /**
   Compute Screen Space Ambient Occlusion.
  
   This pass is very expensive due to the fact that it reads a large amount
   of data from textures and buffers from random locations. It requires a
   separate pass since it writes to the AO texture.
   */
  private func renderSSAO(target: MTLTexture, buffer: MTLCommandBuffer) {
    
    let ssaoPass = MTLRenderPassDescriptor()
    ssaoPass.colorAttachments[0].texture = fboSSAOEnv
    ssaoPass.colorAttachments[0].loadAction = .Load
    ssaoPass.colorAttachments[0].storeAction = .Store
    ssaoPass.depthAttachment.loadAction = .Load
    ssaoPass.depthAttachment.storeAction = .DontCare
    ssaoPass.depthAttachment.texture = fboDepthStencil
    ssaoPass.stencilAttachment.loadAction = .Load
    ssaoPass.stencilAttachment.storeAction = .DontCare
    ssaoPass.stencilAttachment.texture = fboDepthStencil

    let ssaoEncoder = buffer.renderCommandEncoderWithDescriptor(ssaoPass)
    ssaoEncoder.label = "SSAO"
    ssaoEncoder.setStencilReferenceValue(0xF0)
    ssaoEncoder.setDepthStencilState(quadLE)
    ssaoEncoder.setRenderPipelineState(ssaoRenderState)
    ssaoEncoder.setVertexBuffer(quadVBO, offset: 0, atIndex: 0)
    ssaoEncoder.setFragmentBuffer(paramBuffer, offset: 0, atIndex: 0)
    ssaoEncoder.setFragmentBuffer(ssaoSampleBuffer, offset: 0, atIndex: 1)
    ssaoEncoder.setFragmentBuffer(ssaoRandomBuffer, offset: 0, atIndex: 2)
    ssaoEncoder.setFragmentTexture(fboDepthStencil, atIndex: 0)
    ssaoEncoder.setFragmentTexture(fboNormal, atIndex: 1)
    ssaoEncoder.drawPrimitives(.Triangle, vertexStart: 0, vertexCount: 6)
    ssaoEncoder.endEncoding()
  }
  
  /**
   Blur the SSAO texture using a 4x4 box blur.
   */
  private func renderSSAOBlur(target: MTLTexture, buffer: MTLCommandBuffer) {
    
    let blurPass = MTLRenderPassDescriptor()
    blurPass.colorAttachments[0].texture = fboSSAOBlurEnv
    blurPass.colorAttachments[0].loadAction = .Clear
    blurPass.colorAttachments[0].storeAction = .Store
    blurPass.colorAttachments[0].clearColor = MTLClearColorMake(1, 0, 1, 1)
    blurPass.depthAttachment.loadAction = .DontCare
    blurPass.depthAttachment.storeAction = .DontCare
    blurPass.depthAttachment.texture = fboDepthStencil
    blurPass.stencilAttachment.loadAction = .Load
    blurPass.stencilAttachment.storeAction = .DontCare
    blurPass.stencilAttachment.texture = fboDepthStencil

    let blurEncoder = buffer.renderCommandEncoderWithDescriptor(blurPass)
    blurEncoder.label = "SSAOBlur"
    blurEncoder.setStencilReferenceValue(0xF0)
    blurEncoder.setDepthStencilState(quadLE)
    blurEncoder.setRenderPipelineState(ssaoBlurState)
    blurEncoder.setVertexBuffer(quadVBO, offset: 0, atIndex: 0)
    blurEncoder.setFragmentTexture(fboSSAOEnv, atIndex: 0)
    blurEncoder.drawPrimitives(.Triangle, vertexStart: 0, vertexCount: 6)
    blurEncoder.endEncoding()
  }
  
  /**
   Draw the background texture.
   
   In order to reduce the amount of pixels highlighted by the background
   texture, stencil testing is used to discard those regions which are
   occluded by objects rendered on top of the scene. The background texture
   is combined with the AO map to occlude a planar region around objects.
   */
  private func renderBackground(target: MTLTexture, buffer: MTLCommandBuffer) {
  
    let backgroundPass = MTLRenderPassDescriptor()
    backgroundPass.colorAttachments[0].texture = target
    backgroundPass.colorAttachments[0].loadAction = .Clear
    backgroundPass.colorAttachments[0].storeAction = .Store
    backgroundPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
    backgroundPass.depthAttachment.loadAction = .Load
    backgroundPass.depthAttachment.storeAction = .DontCare
    backgroundPass.depthAttachment.texture = fboDepthStencil
    backgroundPass.stencilAttachment.loadAction = .Load
    backgroundPass.stencilAttachment.storeAction = .DontCare
    backgroundPass.stencilAttachment.texture = fboDepthStencil
    
    let backgroundEncoder = buffer.renderCommandEncoderWithDescriptor(backgroundPass)
    backgroundEncoder.label = "Background"
    backgroundEncoder.setStencilReferenceValue(0xF0)
    backgroundEncoder.setDepthStencilState(quadGE)
    backgroundEncoder.setRenderPipelineState(backgroundRenderState)
    backgroundEncoder.setVertexBuffer(quadVBO, offset: 0, atIndex: 0)
    backgroundEncoder.setFragmentTexture(backgroundTexture, atIndex: 0)
    backgroundEncoder.setFragmentTexture(fboSSAOBlurEnv, atIndex: 1)
    backgroundEncoder.drawPrimitives(.Triangle, vertexStart: 0, vertexCount: 6)
    backgroundEncoder.endEncoding()
  }
  
  /**
   Apply all the light sources.
   
   Ligh sources are batched in groups of 32 and only those pixels are shaded
   which belong to an object that was rendered previously. Also, the normal
   matrix is applied to the light direction in order to avoid a matrix
   multiplication and normalization in the fragment shader.
   */
  private func renderLights(target: MTLTexture, buffer: MTLCommandBuffer) {
    
    let lightPass = MTLRenderPassDescriptor()
    lightPass.colorAttachments[0].texture = target
    lightPass.colorAttachments[0].loadAction = .Load
    lightPass.colorAttachments[0].storeAction = .Store
    lightPass.depthAttachment.loadAction = .DontCare
    lightPass.depthAttachment.storeAction = .DontCare
    lightPass.depthAttachment.texture = fboDepthStencil
    lightPass.stencilAttachment.loadAction = .Load
    lightPass.stencilAttachment.storeAction = .DontCare
    lightPass.stencilAttachment.texture = fboDepthStencil
    
    let lightEncoder = buffer.renderCommandEncoderWithDescriptor(lightPass)
    lightEncoder.label = "Lighting"
    lightEncoder.setStencilReferenceValue(0xFF)
    lightEncoder.setDepthStencilState(quadLE)
    lightEncoder.setRenderPipelineState(lightingRenderState)
    lightEncoder.setVertexBuffer(quadVBO, offset: 0, atIndex: 0)
    lightEncoder.setFragmentBuffer(paramBuffer, offset: 0, atIndex: 0)
    lightEncoder.setFragmentTexture(fboDepthStencil, atIndex: 0)
    lightEncoder.setFragmentTexture(fboNormal, atIndex: 1)
    lightEncoder.setFragmentTexture(fboMaterial, atIndex: 2)
    lightEncoder.setFragmentTexture(fboSSAOBlurEnv, atIndex: 3)
    lightEncoder.setFragmentTexture(envMap, atIndex: 4)
    
    for var batch = 0; batch < lights.count; batch += kLightBatch {
      
      // Create a buffer to hold light parameters.
      let lightBuffer = device.newBufferWithLength(
        sizeof(Light) * kLightBatch,
        options: MTLResourceOptions()
      )
      
      // Fill in the buffer with light parameters.
      var data = UnsafeMutablePointer<Light>(lightBuffer.contents())
      let size = min(kLightBatch, lights.count - batch)
      for var i = 0; i < size; ++i {
        let light = lights[batch + i]
        let n: float4 = viewMat.inverse.transpose * float4(
            light.direction.x,
            light.direction.y,
            light.direction.z,
            1
        )
        let l = -Float(sqrt(n.x * n.x + n.y * n.y + n.z * n.z))
        
        data.memory.direction = float4(
            n.x / l,
            n.y / l,
            n.z / l,
            0.0
        )
        data.memory.ambient = float4(
            light.ambient.x,
            light.ambient.y,
            light.ambient.z,
            1.0
        )
        data.memory.diffuse = float4(
            light.diffuse.x,
            light.diffuse.y,
            light.diffuse.z,
            1.0
        )
        data.memory.specular = float4(
            light.specular.x,
            light.specular.y,
            light.specular.z,
            1.0
        )
        
        data = data.successor()
      }
      
      for var i = size; i < kLightBatch; ++i {
        data.memory.direction = float4(0, 0, 0, 1)
        data.memory.ambient = float4(0, 0, 0, 1)
        data.memory.diffuse = float4(0, 0, 0, 1)
        data.memory.specular = float4(0, 0, 0, 1)
        data = data.successor()
      }
      
      lightEncoder.setFragmentBuffer(lightBuffer, offset: 0, atIndex: 1)
      lightEncoder.drawPrimitives(.Triangle, vertexStart: 0, vertexCount: 6)
    }
    
    lightEncoder.endEncoding()
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
      .RG16Snorm,
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
    let fboSSAOEnvDesc = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
      .RG16Float,
      width: width,
      height: height,
      mipmapped: false
    )
    fboSSAOEnv = device.newTextureWithDescriptor(fboSSAOEnvDesc)
    fboSSAOEnv.label = "FBOAOEnv"
    fboSSAOBlurEnv = device.newTextureWithDescriptor(fboSSAOEnvDesc)
    fboSSAOBlurEnv.label = "FBOSSAOBlurEnv"
  }

  /**
   Initializes all FX programs.
   */
  private func setupFXPrograms() throws {
    
    // Depth state to compare stencil reference with GE.
    let quadStencilGE = MTLStencilDescriptor()
    quadStencilGE.stencilCompareFunction = .GreaterEqual
    quadStencilGE.stencilFailureOperation = .Keep
    quadStencilGE.depthFailureOperation = .Keep
    quadStencilGE.depthStencilPassOperation = .Keep
    quadStencilGE.readMask = 0xFF
    quadStencilGE.writeMask = 0x00
    let quadGEDesc = MTLDepthStencilDescriptor()
    quadGEDesc.depthCompareFunction = .Always
    quadGEDesc.depthWriteEnabled = false
    quadGEDesc.frontFaceStencil = quadStencilGE
    quadGEDesc.backFaceStencil = quadStencilGE
    quadGE = device.newDepthStencilStateWithDescriptor(quadGEDesc)
    
    // Depth state to compare stencil reference with LE.
    let quadStencilLE = MTLStencilDescriptor()
    quadStencilLE.stencilCompareFunction = .LessEqual
    quadStencilLE.stencilFailureOperation = .Keep
    quadStencilLE.depthFailureOperation = .Keep
    quadStencilLE.depthStencilPassOperation = .Keep
    quadStencilLE.readMask = 0xFF
    quadStencilLE.writeMask = 0x00
    let quadLEDesc = MTLDepthStencilDescriptor()
    quadLEDesc.depthCompareFunction = .Always
    quadLEDesc.depthWriteEnabled = false
    quadLEDesc.frontFaceStencil = quadStencilLE
    quadLEDesc.backFaceStencil = quadStencilLE
    quadLE = device.newDepthStencilStateWithDescriptor(quadLEDesc)
    
    // Initialize the VBO of the full-screen quad.
    var vbo : [Float] = [
      -1, -1, -1,  1,  1,  1,
      -1, -1,  1,  1,  1, -1,
    ]
    quadVBO = device.newBufferWithBytes(
      vbo,
      length: sizeofValue(vbo[0]) * vbo.count,
      options: MTLResourceOptions()
    )
    quadVBO.label = "VBOQuad"
    
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
    
    // Create the background texture. Data is uploaded from the camera.
    let backgroundTextureDesc = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
      .BGRA8Unorm,
      width: Int(640),
      height: Int(360),
      mipmapped: false
    )
    backgroundTexture = device.newTextureWithDescriptor(backgroundTextureDesc)
    
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
    ssaoRenderDesc.colorAttachments[0].pixelFormat = .RG16Float
    ssaoRenderDesc.colorAttachments[0].writeMask = MTLColorWriteMask.Red
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
    ssaoBlurDesc.colorAttachments[0].pixelFormat = .RG16Float
    ssaoBlurDesc.stencilAttachmentPixelFormat = .Depth32Float_Stencil8
    ssaoBlurDesc.depthAttachmentPixelFormat = .Depth32Float_Stencil8
    ssaoBlurState = try device.newRenderPipelineStateWithDescriptor(ssaoBlurDesc)
  }

  /**
   Sets up SSAO.
   */
  private func setupSSAOBuffers() throws {

    // Set up a buffer with 32 sample vectors. The shader might choose to
    // use only a subset of these in order to increase performance.
    ssaoSampleBuffer = device.newBufferWithBytes(
      ARSceneRenderer.kSSAOSampleData,
      length:
          sizeofValue(ARSceneRenderer.kSSAOSampleData[0]) *
          ARSceneRenderer.kSSAOSampleData.count,
      options: MTLResourceOptions()
    )
    ssaoSampleBuffer.label = "VBOSSAOSampleBuffer"

    // Set up a 4x4 texture with randomly selected vectors with x, y \in [0, 1].
    ssaoRandomBuffer = device.newBufferWithBytes(
      ARSceneRenderer.kSSAORandomData,
      length:
          sizeofValue(ARSceneRenderer.kSSAORandomData[0]) *
          ARSceneRenderer.kSSAORandomData.count,
      options: MTLResourceOptions()
    )
    ssaoRandomBuffer.label = "VBOSSSAORandomBuffer"
  }
  
  /**
   Sets up the renderer for the pedestal.
   */
  private func setupPedestal() throws {

    // Set up the depth state for objects.
    let pedestalStencil = MTLStencilDescriptor()
    pedestalStencil.stencilCompareFunction = .Greater
    pedestalStencil.depthStencilPassOperation = .Replace
    pedestalStencil.stencilFailureOperation = .Keep
    pedestalStencil.depthFailureOperation = .Keep
    pedestalStencil.readMask = 0xFF
    pedestalStencil.writeMask = 0xFF
    
    let pedestalDepthDesc = MTLDepthStencilDescriptor()
    pedestalDepthDesc.depthCompareFunction = .Less
    pedestalDepthDesc.depthWriteEnabled = true
    pedestalDepthDesc.frontFaceStencil = pedestalStencil
    pedestalDepthDesc.backFaceStencil = pedestalStencil
    pedestalDepthState = device.newDepthStencilStateWithDescriptor(pedestalDepthDesc)
    
    // Set up the shaders for the pedestal.
    guard let pedestalVert = library.newFunctionWithName("pedestalVert") else {
      throw ARRendererError.MissingFunction
    }
    guard let pedestalFrag = library.newFunctionWithName("pedestalFrag") else {
      throw ARRendererError.MissingFunction
    }
    
    // Create the pipeline descriptor.
    let pedestalRenderDesc = MTLRenderPipelineDescriptor()
    pedestalRenderDesc.sampleCount = 1
    pedestalRenderDesc.vertexFunction = pedestalVert
    pedestalRenderDesc.fragmentFunction = pedestalFrag
    pedestalRenderDesc.colorAttachments[0].pixelFormat = .RG16Snorm
    pedestalRenderDesc.depthAttachmentPixelFormat = .Depth32Float_Stencil8
    pedestalRenderDesc.stencilAttachmentPixelFormat = .Depth32Float_Stencil8
    pedestalRenderState = try device.newRenderPipelineStateWithDescriptor(pedestalRenderDesc)
    
    // Pedestal buffer data.
    let vbo: [float4] = [
        float4( 6.0,  6.0, 0, 1),
        float4(-6.0, -6.0, 0, 1),
        float4(-6.0,  6.0, 0, 1),
        float4(-6.0, -6.0, 0, 1),
        float4( 6.0,  6.0, 0, 1),
        float4( 6.0, -6.0, 0, 1),
    ]
    pedestalBuffer = device.newBufferWithBytes(
        vbo,
        length: sizeofValue(vbo[0]) * vbo.count,
        options: MTLResourceOptions()
    )
    pedestalBuffer.label = "VBOPedestal"
  }
  
  /**
   Sets up the object rendering state.
   */
  private func setupObject() throws {
    
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
    objectRenderDesc.colorAttachments[0].pixelFormat = .RG16Snorm
    objectRenderDesc.colorAttachments[1].pixelFormat = .RGBA8Unorm
    objectRenderDesc.colorAttachments[2].pixelFormat = .RG16Float
    objectRenderDesc.depthAttachmentPixelFormat = .Depth32Float_Stencil8
    objectRenderDesc.stencilAttachmentPixelFormat = .Depth32Float_Stencil8
    objectRenderState = try device.newRenderPipelineStateWithDescriptor(objectRenderDesc)
  }
  
  /**
   Sets up the environment map.
   */
  private func setupEnvironmentMap(map: UIImage) throws {
    
    // Two channels store the x and y components of a normal vector.
    let envMapDesc = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
      .BGRA8Unorm,
      width: Int(map.size.width),
      height: Int(map.size.height),
      mipmapped: false
    )
    envMap = device.newTextureWithDescriptor(envMapDesc)
    envMap.label = "TEXEnvMap"

    map.toMTLTexture(envMap)
  }
  
  
  // 32 random vectors in a hemisphere.
  private static let kSSAOSampleData: [float4] = [
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
  
  // 4x4 random texture.
  private static let kSSAORandomData: [float4] = [
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
}
