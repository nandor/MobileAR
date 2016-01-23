// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import Metal

/**
 Renders an environment map over on a sphere around the origin.
 */
class AREnvironmentViewRenderer : ARRenderer {

  // Spherical texture to be displayed.
  var texture: MTLTexture!

  // Depth buffer state.
  var depthState: MTLDepthStencilState!

  // Renderer state.
  var renderState: MTLRenderPipelineState!

  // Vertex buffer for the spherical mesh.
  var sphereVBO: MTLBuffer!

  // Index buffer for the spherical mesh.
  var sphereIBO: MTLBuffer!


  /**
   Initializes the environment renderer.
   */
  init(view: UIView, environment: AREnvironment) throws {
    try super.init(view: view)

    // Create the texture.
    let texDesc = MTLTextureDescriptor()
    texDesc.textureType = .Type2D
    texDesc.height = 100
    texDesc.width = 100
    texDesc.depth = 1
    texDesc.pixelFormat = .BGRA8Unorm
    texDesc.arrayLength = 1
    texDesc.mipmapLevelCount = 1
    texture = device.newTextureWithDescriptor(texDesc)

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
  }

  /**
   Renders the environment.
   */
  override func renderScene(texture: MTLTexture, buffer: MTLCommandBuffer) {

    // Create the render command descriptor.
    let renderDesc = MTLRenderPassDescriptor()
    let color = renderDesc.colorAttachments[0]
    color.texture = texture
    color.loadAction = .Clear
    color.storeAction = .Store
    color.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
    let encoder = buffer.renderCommandEncoderWithDescriptor(renderDesc)

    // Render the sphere.
    encoder.setDepthStencilState(depthState)
    encoder.setRenderPipelineState(renderState)
    encoder.setVertexBuffer(params, offset: 0, atIndex: 0)
    encoder.setVertexBuffer(sphereVBO, offset: 0, atIndex: 1)
    encoder.drawIndexedPrimitives(
        .Triangle,
        indexCount: 36,
        indexType: .UInt16,
        indexBuffer: sphereIBO,
        indexBufferOffset: 0
    )

    encoder.endEncoding()
  }
}
