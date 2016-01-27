// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import UIKit
import Metal

/**
 Renders the augmented scene.
 */
class ARSceneRenderer : ARRenderer {


  /**
   Initializes the renderer.
   */
  override init(view: UIView) throws {
    try super.init(view: view)
  }

  /**
   Renders a single frame.
   */
  override func onRenderFrame(target: MTLTexture, buffer: MTLCommandBuffer) {

    // Create the render command descriptor.
    let renderDesc = MTLRenderPassDescriptor()
    let color = renderDesc.colorAttachments[0]
    color.texture = target
    color.loadAction = .Clear
    color.storeAction = .Store
    color.clearColor = MTLClearColorMake(0.0, 1.0, 0.0, 1.0)
    
    let encoder = buffer.renderCommandEncoderWithDescriptor(renderDesc)
    encoder.endEncoding()
  }
}
