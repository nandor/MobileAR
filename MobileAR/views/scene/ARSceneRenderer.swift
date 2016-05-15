// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import UIKit
import Metal



// Number of light sources to render in a batch.
private let kLightBatch = 32
// Number of objects to render in an instance batch.
private let kInstanceBatch = 32


/**
 Render buffer for the scene.
 
 Besides the camera pose, it also holds model matrices for objects, pedestals,
 as well as parameters for the light sources. The data structures map the batch
 index to a buffer holding enough elements to render a batch.
 */
class ARSceneRenderBuffer: ARRenderBuffer {
  internal var models = ARBatchBuffer()
  internal var lights = ARBatchBuffer()
  internal var pedestals = ARBatchBuffer()
}


/**
 Renders the augmented scene.
 */
class ARSceneRenderer: ARRenderer<ARSceneRenderBuffer> {

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
  private var fboFXAA: MTLTexture!

  // Data to render the quad spanning the entire screen.
  private var quadLE: MTLDepthStencilState!
  private var quadGE: MTLDepthStencilState!
  private var quadAW: MTLDepthStencilState!
  private var quadVBO: MTLBuffer!

  // Shader to render the background.
  private var backgroundRenderState: MTLRenderPipelineState!
  private var backgroundTexture: MTLTexture!

  // Shader to apply phong shaders.
  private var lightingRenderState: MTLRenderPipelineState!

  // Shader to do FXAA.
  private var fxaaRenderState: MTLRenderPipelineState!
  
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

  // Objects to be rendered.
  internal var objects: [ARObject] = []
  // Light sources to be used.
  internal var lights: [ARLight] = []


  /**
   Initializes the renderer.
   */
  init(view: UIView, environment: AREnvironment) throws {
    try super.init(view: view, buffers: 3)

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
  override func onRenderFrame(
      buffer: MTLCommandBuffer,
      params: ARSceneRenderBuffer)
  {
    renderGeometry(buffer, params: params)
    renderPedestals(buffer, params: params)
    renderSSAO(buffer, params: params)
    renderSSAOBlur(buffer, params: params)
    renderBackground(buffer, params: params)
    renderLights(buffer, params: params)
    renderFXAA(buffer, params: params)
  }

  /**
   Pass to render to the geometry buffer.

   This pass renders all objects and writes to the depth buffer, sets
   all pixels to 0xFF in the stencil buffer, writes the albedo + specular
   exponent to the material buffer and saves the X and Y components of the
   normalized normal vectors into the normal buffer.
   */
  private func renderGeometry(
      buffer: MTLCommandBuffer,
      params: ARSceneRenderBuffer)
  {
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
          geomEncoder.setVertexBuffer(params.poseBuffer, offset: 0, atIndex: 1)
          geomEncoder.setFragmentTexture(mesh.texDiffuse, atIndex: 0)
          geomEncoder.setFragmentTexture(mesh.texSpecular, atIndex: 1)
          geomEncoder.setFragmentTexture(mesh.texNormal, atIndex: 2)

          for batch in 0.stride(to: mats.count, by: kInstanceBatch) {

            // Create or fetch a temporary buffer to store object parameters.
            let modelBuffer = params.models.get(batch, create: {
              return self.device.newBufferWithLength(
                  sizeof(ARObjectParameters) * kInstanceBatch,
                  options: MTLResourceOptions()
              )
            })

            // Fill in the buffer with model matrices.
            var data = UnsafeMutablePointer<ARObjectParameters>(modelBuffer.contents())
            let size = min(kInstanceBatch, mats.count - batch)
            for i in 0..<size {
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
  private func renderPedestals(
      buffer: MTLCommandBuffer,
      params: ARSceneRenderBuffer)
  {
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
    pedestalEncoder.setVertexBuffer(params.poseBuffer, offset: 0, atIndex: 1)

    for batch in 0.stride(to: objects.count, by: kInstanceBatch) {

      // Create a temporary buffer to store object parameters.
      let modelBuffer = params.pedestals.get(batch, create: {
        return self.device.newBufferWithLength(
            sizeof(ARObjectParameters) * kInstanceBatch,
            options: MTLResourceOptions()
        )
      })

      // Fill in the buffer with model matrices.
      var data = UnsafeMutablePointer<ARObjectParameters>(modelBuffer.contents())
      let size = min(kInstanceBatch, objects.count - batch)
      for i in 0..<size {
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
  private func renderSSAO(
      buffer: MTLCommandBuffer,
      params: ARSceneRenderBuffer)
  {
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
    ssaoEncoder.setFragmentBuffer(params.poseBuffer, offset: 0, atIndex: 0)
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
  private func renderSSAOBlur(
      buffer: MTLCommandBuffer,
      params: ARSceneRenderBuffer)
  {
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
  private func renderBackground(
      buffer: MTLCommandBuffer,
      params: ARSceneRenderBuffer)
  {
    let backgroundPass = MTLRenderPassDescriptor()
    backgroundPass.colorAttachments[0].texture = fboFXAA
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
  private func renderLights(
      buffer: MTLCommandBuffer,
      params: ARSceneRenderBuffer)
  {
    let lightPass = MTLRenderPassDescriptor()
    lightPass.colorAttachments[0].texture = fboFXAA
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
    lightEncoder.setFragmentBuffer(params.poseBuffer, offset: 0, atIndex: 0)
    lightEncoder.setFragmentTexture(fboDepthStencil, atIndex: 0)
    lightEncoder.setFragmentTexture(fboNormal, atIndex: 1)
    lightEncoder.setFragmentTexture(fboMaterial, atIndex: 2)
    lightEncoder.setFragmentTexture(fboSSAOBlurEnv, atIndex: 3)
    lightEncoder.setFragmentTexture(envMap, atIndex: 4)

    for batch in 0.stride(to: lights.count, by: kLightBatch) {
      
      // Create or fetch a buffer to hold light parameters.
      let lightBuffer = params.lights.get(batch, create: {
        return self.device.newBufferWithLength(
            sizeof(Light) * kLightBatch,
            options: MTLResourceOptions()
        )
      })

      // Fill in the buffer with light parameters.
      var data = UnsafeMutablePointer<Light>(lightBuffer.contents())
      let size = min(kLightBatch, lights.count - batch)
      for i in 0..<size {
        let light = lights[batch + i]
        data.memory.direction = -params.viewMat * float4(
            light.direction.x,
            light.direction.y,
            light.direction.z,
            0
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
      
      for _ in size..<kLightBatch {
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
   Runs the FXAA shader on the final, tone-mapped RGB colour output.
   */
  private func renderFXAA(
      buffer: MTLCommandBuffer,
      params: ARSceneRenderBuffer)
  {
    let fxaaPass = MTLRenderPassDescriptor()
    fxaaPass.colorAttachments[0].texture = drawable.texture
    fxaaPass.colorAttachments[0].loadAction = .DontCare
    fxaaPass.colorAttachments[0].storeAction = .Store
    
    let fxaaEncoder = buffer.renderCommandEncoderWithDescriptor(fxaaPass)
    fxaaEncoder.label = "FXAA"
    fxaaEncoder.setRenderPipelineState(fxaaRenderState)
    fxaaEncoder.setVertexBuffer(quadVBO, offset: 0, atIndex: 0)
    fxaaEncoder.setFragmentTexture(fboFXAA, atIndex: 0)
    fxaaEncoder.drawPrimitives(.Triangle, vertexStart: 0, vertexCount: 6)
    fxaaEncoder.endEncoding()
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
    
    // Colour output as FXAA input.
    let fboFXAADesc = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
      .BGRA8Unorm,
      width: width,
      height: height,
      mipmapped: true
    )
    fboFXAA = device.newTextureWithDescriptor(fboFXAADesc)
    fboFXAA.label = "FBOFXAA"

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
    
    // Depth state to always render a quad.
    let quadAWDesc = MTLDepthStencilDescriptor()
    quadAWDesc.depthCompareFunction = .Always
    quadAWDesc.depthWriteEnabled = false
    quadAW = device.newDepthStencilStateWithDescriptor(quadAWDesc)

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
    
    // Fragment shader to perform FXAA.
    guard let fxaa = library.newFunctionWithName("fxaa") else {
      throw ARRendererError.MissingFunction
    }
    let fxaaDesc = MTLRenderPipelineDescriptor()
    fxaaDesc.sampleCount = 1
    fxaaDesc.vertexFunction = fullscreen
    fxaaDesc.fragmentFunction = fxaa
    fxaaDesc.colorAttachments[0].pixelFormat = .BGRA8Unorm
    fxaaRenderState = try device.newRenderPipelineStateWithDescriptor(fxaaDesc)
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
        float4( 3.0,  3.0, 0.0, 1),
        float4(-3.0,  3.0, 0.0, 1),
        float4(-3.0, -3.0, 0.0, 1),
        float4(-3.0, -3.0, 0.0, 1),
        float4( 3.0, -3.0, 0.0, 1),
        float4( 3.0,  3.0, 0.0, 1),
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
    float4(-0.0752914292, -0.0277232259,  0.0615988864, 0.0),
    float4( 0.0876286654,  0.0886048422,  0.0987327402, 0.0),
    float4(-0.0234147542, -0.0573714530,  0.1182104081, 0.0),
    float4( 0.1148563821,  0.1592088896,  0.1328043926, 0.0),
    float4( 0.0320630400, -0.0794050733,  0.0766371546, 0.0),
    float4(-0.0794997448,  0.0716646517,  0.2158426004, 0.0),
    float4( 0.0746700883, -0.1809968538,  0.3510182680, 0.0),
    float4(-0.2739931697, -0.1811877564,  0.3363442874, 0.0),
    float4( 0.3290913623,  0.2241600856,  0.3498416831, 0.0),
    float4( 0.2726992813,  0.2527844031,  0.1758128266, 0.0),
    float4(-0.0814383726, -0.0903451891,  0.2384033188, 0.0),
    float4(-0.2067708640,  0.1686499438,  0.2548883735, 0.0),
    float4( 0.1538638376,  0.0689878666,  0.2351656747, 0.0),
    float4( 0.1749262241,  0.1568768405,  0.1850898637, 0.0),
    float4(-0.2843830634, -0.1312189126,  0.1572129509, 0.0),
    float4( 0.2009544205, -0.1032315027,  0.1792585139, 0.0),
    float4( 0.0027638778, -0.0429469064,  0.1108274169, 0.0),
    float4(-0.2231133147, -0.0198895552,  0.1435858589, 0.0),
    float4( 0.2283580407,  0.2391308702,  0.3471880971, 0.0),
    float4( 0.0785196088, -0.3883981109,  0.3226263188, 0.0),
    float4(-0.1547655310,  0.5230170828,  0.3650077910, 0.0),
    float4(-0.3571472166, -0.0425048554,  0.2950925856, 0.0),
    float4( 0.1469349718,  0.2795888925,  0.3220045265, 0.0),
    float4(-0.0638066493, -0.1034330801,  0.1590781274, 0.0),
    float4(-0.0672072150,  0.1035306586,  0.1234430248, 0.0),
    float4( 0.0074377900, -0.0681982910,  0.2358700841, 0.0),
    float4(-0.4664843421,  0.1545208140,  0.6685794793, 0.0),
    float4( 0.0178721751,  0.0916408558,  0.0528855818, 0.0),
    float4(-0.5645181201, -0.4623589554,  0.3051214450, 0.0),
    float4(-0.0715112940,  0.0176278802,  0.2040827009, 0.0),
    float4(-0.3989055220, -0.3219091643,  0.3658657834, 0.0),
    float4( 0.1992279618,  0.2274140061,  0.1662010934, 0.0),
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
