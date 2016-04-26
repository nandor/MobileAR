// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import Darwin
import Metal


// Number of slices in the sphere.
let kSphereSlices: Int = 16
// Number of stacks in the sphere.
let kSphereStacks: Int = 16
// Number of lights to render in a pass.
let kEnvLightBatch = 32

/**
 Stores the compositing state.
 */
class AREnvironmentRenderBuffer: ARRenderBuffer {
  // Pose of image to be composited.
  private var compositeParam: MTLBuffer!
  // Image to be composited.
  private var compositeTexture: MTLTexture!
  // Light sources to be displayed.
  private var lights = ARBatchBuffer()
  
  required init(device: MTLDevice) {
    super.init(device: device)
    
    // Buffer to hold the projection matrix.
    compositeParam = device.newBufferWithLength(
        sizeof(float4x4),
        options: MTLResourceOptions()
    )
    compositeParam.label = "VBOComposite"
    
    // Source texture.
    let compositeTextureDesc = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
        .BGRA8Unorm,
        width: Int(640),
        height: Int(360),
        mipmapped: false
    )
    compositeTexture = device.newTextureWithDescriptor(compositeTextureDesc)
    compositeTexture.label = "TEXComposite"
  }
}

/**
 Renders an environment map over on a sphere around the origin.
 */
class AREnvironmentViewRenderer: ARRenderer<AREnvironmentRenderBuffer> {
  
  // Light information.
  private struct Light {
    var direction: float4
    var diffuse: float4
  }
  
  // Depth buffer state.
  private var depthState: MTLDepthStencilState!
  // Renderer state.
  private var envSphereState: MTLRenderPipelineState!
  // Renderer state for lights.
  private var envLightState: MTLRenderPipelineState!
  // Vertex buffer for the spherical mesh.
  private var sphereVBO: MTLBuffer!
  // Index buffer for the spherical mesh.
  private var sphereIBO: MTLBuffer!
  // Vertex buffer for a quad.
  private var quadVBO: MTLBuffer!
  
  // Spherical texture to be displayed.
  private var texture: MTLTexture!
  // List of lights to be rendered
  private var lights: [ARLight] = []
  
  // Compositing state.
  private var compositeState: MTLComputePipelineState!
  // Flag to ensure that a single image is being uploaded at a time.
  private var compositing: Bool = false
  // Queue of images to be composited.
  private var compositeQueue: [(UIImage, ARPose)] = []
  
  // Width & height of the environment map.
  private var envWidth: Int = 0
  private var envHeight: Int = 0

  /**
   Initializes the environment renderer using an existing environment.
   */
  required init(view: UIView) throws {
    try super.init(view: view, buffers: 3)

    // Set up the depth state.
    let depthDesc = MTLDepthStencilDescriptor()
    depthDesc.depthCompareFunction = .Always
    depthDesc.depthWriteEnabled = false
    depthState = device.newDepthStencilStateWithDescriptor(depthDesc)

    // Pipeline state for scene rendering.
    guard let envSphereVert = library.newFunctionWithName("envSphereVert") else {
      throw ARRendererError.MissingFunction
    }
    guard let envSphereFrag = library.newFunctionWithName("envSphereFrag") else {
      throw ARRendererError.MissingFunction
    }
    let envSphereDesc = MTLRenderPipelineDescriptor()
    envSphereDesc.sampleCount = 1
    envSphereDesc.vertexFunction = envSphereVert
    envSphereDesc.fragmentFunction = envSphereFrag
    envSphereDesc.colorAttachments[0].pixelFormat = .BGRA8Unorm
    envSphereState = try device.newRenderPipelineStateWithDescriptor(envSphereDesc)
    
    // Pipeline state for light rendering.
    guard let envLightVert = library.newFunctionWithName("envLightVert") else {
      throw ARRendererError.MissingFunction
    }
    guard let envLightFrag = library.newFunctionWithName("envLightFrag") else {
      throw ARRendererError.MissingFunction
    }
    let envLightDesc = MTLRenderPipelineDescriptor()
    envLightDesc.sampleCount = 1
    envLightDesc.vertexFunction = envLightVert
    envLightDesc.fragmentFunction = envLightFrag
    envLightDesc.colorAttachments[0].rgbBlendOperation = .Add
    envLightDesc.colorAttachments[0].alphaBlendOperation = .Add
    envLightDesc.colorAttachments[0].sourceRGBBlendFactor = .SourceAlpha
    envLightDesc.colorAttachments[0].sourceAlphaBlendFactor = .SourceAlpha
    envLightDesc.colorAttachments[0].destinationRGBBlendFactor = .OneMinusSourceAlpha
    envLightDesc.colorAttachments[0].destinationAlphaBlendFactor = .OneMinusSourceAlpha
    envLightDesc.colorAttachments[0].pixelFormat = .BGRA8Unorm
    envLightDesc.colorAttachments[0].blendingEnabled = true
    envLightState = try device.newRenderPipelineStateWithDescriptor(envLightDesc)

    // Initialize the VBO of the sphere.
    // The coordinate system is a bit funny since CoreMotion uses a coordinate
    // system where X points to north and Z points upwards. Thus, we swap
    // Z with Y and invert the Z axis.
    var vbo = [Float](count: (kSphereSlices + 1) * (kSphereStacks + 1) * 3, repeatedValue: 0.0)
    for st in 0...kSphereStacks {
      let s = Double(st) / Double(kSphereStacks)
      let phi = M_PI / 2.0 - s * M_PI

      for sl in 0...kSphereSlices {
        let t = Double(sl) / Double(kSphereSlices)
        let theta = t * M_PI * 2.0
        let idx = (st * (kSphereSlices + 1) + sl) * 3

        vbo[idx + 0] = Float(cos(phi) * cos(theta))
        vbo[idx + 1] = Float(cos(phi) * sin(theta))
        vbo[idx + 2] = Float(sin(phi))
      }
    }
    sphereVBO = device.newBufferWithBytes(
        vbo,
        length: sizeofValue(vbo[0]) * vbo.count,
        options: MTLResourceOptions()
    )
    sphereVBO.label = "VBOSphere"

    // Initialize the IBO of the sphere.
    var ibo = [UInt32](count: kSphereSlices * kSphereStacks * 6, repeatedValue: 0)
    for st in 0...kSphereStacks - 1 {
      for sl in 0...kSphereSlices - 1 {

        let idx = (st * kSphereSlices + sl) * 6
        ibo[idx + 0] = UInt32((st + 0) * (kSphereSlices + 1) + sl + 0)
        ibo[idx + 1] = UInt32((st + 1) * (kSphereSlices + 1) + sl + 0)
        ibo[idx + 2] = UInt32((st + 0) * (kSphereSlices + 1) + sl + 1)
        ibo[idx + 3] = UInt32((st + 0) * (kSphereSlices + 1) + sl + 1)
        ibo[idx + 4] = UInt32((st + 1) * (kSphereSlices + 1) + sl + 0)
        ibo[idx + 5] = UInt32((st + 1) * (kSphereSlices + 1) + sl + 1)
      }
    }
    sphereIBO = device.newBufferWithBytes(
        ibo,
        length: sizeofValue(ibo[0]) * ibo.count,
        options: MTLResourceOptions()
    )
    sphereIBO.label = "IBOSphere"
    
    // Initialize the state for compositing.
    guard let compositeFunc = library.newFunctionWithName("composite") else {
      throw ARRendererError.MissingFunction
    }
    compositeState = try device.newComputePipelineStateWithFunction(compositeFunc)
    
    // Initialize the quad VBO.
    let quad : [Float] = [
      -0.1, -0.1, -0.1,  0.1,  0.1,  0.1,
      -0.1, -0.1,  0.1,  0.1,  0.1, -0.1,
    ]
    quadVBO = device.newBufferWithBytes(
      quad,
      length: sizeofValue(quad) * quad.count,
      options: MTLResourceOptions()
    )
    quadVBO.label = "VBOQuad"
  }

  /**
   Initializes the renderer from an environment.
   */
  convenience init(view: UIView, environment: AREnvironment) throws {

    // Initialize the rest of the stuff.
    try self.init(view: view)
    
    envWidth = Int(environment.map.size.width)
    envHeight = Int(environment.map.size.height)

    // Initialize the environment map texture.
    let texDesc = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
        .BGRA8Unorm,
        width: envWidth,
        height: envHeight,
        mipmapped: false
    )
    texture = device.newTextureWithDescriptor(texDesc)
    texture.label = "TEXEnvironment"
    environment.map.toMTLTexture(texture)
    
    // Fill in the lights.
    lights = environment.lights
  }

  /**
   Initializes the renderer from a given texture size.
   */
  convenience init(view: UIView, width: Int, height: Int) throws {

    // Initialize the rest.
    try self.init(view: view)

    envWidth = width
    envHeight = height
    
    // Initialize the environment map texture.
    let texDesc = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
        .BGRA8Unorm,
        width: width,
        height: height,
        mipmapped: false
    )
    texture = device.newTextureWithDescriptor(texDesc)
    texture.label = "TEXEnvironment"
  }

  /**
   Updates the underlying texture.
   */
  func update(image: UIImage) {
    image.toMTLTexture(texture)
  }
  
  /**
   Updates the underlying texture, compositing an image onto the panorama.
   */
  func update(image: UIImage, pose: ARPose) {
    compositeQueue.append((image, pose))
  }

  /**
   Renders the environment.
   */
  override func onRenderFrame(
      buffer: MTLCommandBuffer,
      params: AREnvironmentRenderBuffer)
  {
    if !compositeQueue.isEmpty {
      let (image, pose) = compositeQueue.removeFirst()
      
      // Upload the image & pose.
      image.toMTLTexture(params.compositeTexture)
      let data = UnsafeMutablePointer<float4x4>(params.compositeParam.contents())
      data.memory = pose.projMat * pose.viewMat
      
      // Compute the thread group size.
      let groupSize  = MTLSizeMake(16, 16, 1);
      let groupCount = MTLSizeMake(
          envWidth / groupSize.width,
          envHeight / groupSize.height,
          1 / groupSize.depth
      )
      
      // Create the composite command descriptor.
      let encoder = buffer.computeCommandEncoder()
      encoder.setComputePipelineState(compositeState)
      encoder.setTexture(params.compositeTexture, atIndex: 0)
      encoder.setTexture(texture, atIndex: 1)
      encoder.setBuffer(params.compositeParam, offset: 0, atIndex: 0)
      encoder.dispatchThreadgroups(groupCount, threadsPerThreadgroup: groupSize)
      encoder.endEncoding()
    }
    
    // Create the render command descriptor.
    let sphereDesc = MTLRenderPassDescriptor()
    sphereDesc.colorAttachments[0].texture = drawable.texture
    sphereDesc.colorAttachments[0].loadAction = .DontCare
    sphereDesc.colorAttachments[0].storeAction = .Store

    // Render the sphere.
    let encoder = buffer.renderCommandEncoderWithDescriptor(sphereDesc)
    encoder.label = "Environment"
    encoder.setDepthStencilState(depthState)
    encoder.setRenderPipelineState(envSphereState)
    encoder.setVertexBuffer(sphereVBO, offset: 0, atIndex: 0)
    encoder.setVertexBuffer(params.poseBuffer, offset: 0, atIndex: 1)
    encoder.setFragmentTexture(texture, atIndex: 0)
    encoder.drawIndexedPrimitives(
        .Triangle,
        indexCount: kSphereSlices * kSphereStacks * 6,
        indexType: .UInt32,
        indexBuffer: sphereIBO,
        indexBufferOffset: 0
    )
    
    // Render lights.
    encoder.setDepthStencilState(depthState)
    encoder.setRenderPipelineState(envLightState)
    encoder.setVertexBuffer(quadVBO, offset: 0, atIndex:  0)
    encoder.setVertexBuffer(params.poseBuffer, offset: 0, atIndex: 1)

    for batch in 0.stride(to: lights.count, by: kEnvLightBatch) {

      // Create or fetch a buffer to hold light parameters.
      let lightBuffer = params.lights.get(batch, create: {
        return self.device.newBufferWithLength(
          sizeof(Light) * kEnvLightBatch,
          options: MTLResourceOptions()
        )
      })

      // Fill in the buffer with light parameters.
      var data = UnsafeMutablePointer<Light>(lightBuffer.contents())
      let size = min(kEnvLightBatch, lights.count - batch)
      let s = Float(lights.count) / 4.0
      for i in 0..<size {
        let light = lights[batch + i]
        data.memory.direction = float4(
          light.direction.x,
          light.direction.y,
          light.direction.z,
          0
        )
        data.memory.diffuse = float4(
          s * light.diffuse.x,
          s * light.diffuse.y,
          s * light.diffuse.z,
          1.0
        )

        data = data.successor()
      }

      // Draw a batch of lights.
      encoder.setVertexBuffer(lightBuffer, offset: 0, atIndex: 2)
      encoder.drawPrimitives(
          .Triangle,
          vertexStart: 0,
          vertexCount: 6,
          instanceCount: size
      )
    }
    encoder.endEncoding()
  }
}
