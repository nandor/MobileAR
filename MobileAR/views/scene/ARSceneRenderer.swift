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
  private var quadDepthState: MTLDepthStencilState!
  private var quadVBO: MTLBuffer!

  // Background render state.
  private var backgroundRenderState: MTLRenderPipelineState!
  private var backgroundTexture: MTLTexture!

  /**
   Initializes the renderer.
   */
  override init(view: UIView) throws {
    try super.init(view: view)

    // Set up the depth state.
    let quadDepthDesc = MTLDepthStencilDescriptor()
    quadDepthDesc.depthCompareFunction = .Always
    quadDepthDesc.depthWriteEnabled = false
    quadDepthState = device.newDepthStencilStateWithDescriptor(quadDepthDesc)

    // Set up the shaders.
    guard let fullscreen = library.newFunctionWithName("fullscreen") else {
      throw ARRendererError.MissingFunction
    }
    guard let background = library.newFunctionWithName("background") else {
      throw ARRendererError.MissingFunction
    }

    // Create the pipeline descriptor.
    let backgroundRenderDesc = MTLRenderPipelineDescriptor()
    backgroundRenderDesc.sampleCount = 1
    backgroundRenderDesc.vertexFunction = fullscreen
    backgroundRenderDesc.fragmentFunction = background
    backgroundRenderDesc.colorAttachments[0].pixelFormat = .BGRA8Unorm
    backgroundRenderState = try device.newRenderPipelineStateWithDescriptor(backgroundRenderDesc)

    // Initialize the VBO of the full-screen quad.
    var vbo : [Float] = [
      -1, -1,
       1,  1,
      -1,  1,
      -1, -1,
       1, -1,
       1,  1
    ]
    quadVBO = device.newBufferWithBytes(
        vbo,
        length: sizeofValue(vbo[0]) * vbo.count,
        options: MTLResourceOptions()
    )

    // Create the background texture.
    let backgroundTextureDesc = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
        .BGRA8Unorm,
        width: Int(640),
        height: Int(360),
        mipmapped: false
    )
    backgroundTexture = device.newTextureWithDescriptor(backgroundTextureDesc)
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

    // Create the render command descriptor.
    let renderDesc = MTLRenderPassDescriptor()
    let color = renderDesc.colorAttachments[0]
    color.texture = target
    color.loadAction = .DontCare
    color.storeAction = .Store

    // Render the full-screen quad.
    let encoder = buffer.renderCommandEncoderWithDescriptor(renderDesc)
    encoder.setDepthStencilState(quadDepthState)
    encoder.setRenderPipelineState(backgroundRenderState)
    encoder.setVertexBuffer(quadVBO, offset: 0, atIndex: 0)
    encoder.setFragmentTexture(backgroundTexture, atIndex: 0)
    encoder.drawPrimitives(.Triangle, vertexStart: 0, vertexCount: 6)
    encoder.endEncoding()
  }
}
