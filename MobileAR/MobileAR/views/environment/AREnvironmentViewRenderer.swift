// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import Darwin
import Metal


// Number of slices in the sphere.
let kSphereSlices: Int = 16
// Number of stacks in the sphere.
let kSphereStacks: Int = 16

/**
 Stores the compositing state.
 */
class AREnvironmentRenderBuffer: ARRenderBuffer {
  // Pose of image to be composited.
  private var compositeParam: MTLBuffer!
  // Image to be composited.
  private var compositeTexture: MTLTexture!
  
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

  // Depth buffer state.
  private var depthState: MTLDepthStencilState!
  // Renderer state.
  private var renderState: MTLRenderPipelineState!
  // Vertex buffer for the spherical mesh.
  private var sphereVBO: MTLBuffer!
  // Index buffer for the spherical mesh.
  private var sphereIBO: MTLBuffer!
  
  // Spherical texture to be displayed.
  private var texture: MTLTexture!
  
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
    depthDesc.depthCompareFunction = .LessEqual
    depthDesc.depthWriteEnabled = true
    depthState = device.newDepthStencilStateWithDescriptor(depthDesc)

    // Set up the shaders.
    guard let vert = library.newFunctionWithName("sphereVert") else {
      throw ARRendererError.MissingFunction
    }
    guard let frag = library.newFunctionWithName("sphereFrag") else {
      throw ARRendererError.MissingFunction
    }

    // Create the pipeline descriptor.
    let renderDesc = MTLRenderPipelineDescriptor()
    renderDesc.sampleCount = 1
    renderDesc.vertexFunction = vert
    renderDesc.fragmentFunction = frag
    renderDesc.colorAttachments[0].pixelFormat = .BGRA8Unorm
    renderState = try device.newRenderPipelineStateWithDescriptor(renderDesc)

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
    let renderDesc = MTLRenderPassDescriptor()
    renderDesc.colorAttachments[0].texture = drawable.texture
    renderDesc.colorAttachments[0].loadAction = .DontCare
    renderDesc.colorAttachments[0].storeAction = .Store

    // Render the sphere.
    let encoder = buffer.renderCommandEncoderWithDescriptor(renderDesc)
    encoder.setDepthStencilState(depthState)
    encoder.setRenderPipelineState(renderState)
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
    encoder.endEncoding()
  }
}
