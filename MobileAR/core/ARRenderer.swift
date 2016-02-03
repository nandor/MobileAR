// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import Darwin
import Metal
import UIKit
import QuartzCore

import simd


/**
 Enumerations of things that can go wrong with the renderer.
 */
enum ARRendererError : ErrorType {
  case MissingFunction
}


/**
 Class that handles rendering using Metal.
 */
class ARRenderer {
  
  /**
   Parameters passed to shaders.
   */
  struct ARCameraParameters {
    /// Perspective projection matrix.
    var proj: float4x4
    /// Inverse projection matrix.
    var invProj: float4x4
    
    /// View matrix.
    var view: float4x4
    /// Normal matrix.
    var normView: float4x4
    /// Inverse view matrix.
    var invView: float4x4
    
    /// Model matrix.
    var model: float4x4
    /// Normal matrix for model.
    var normModel: float4x4
    /// Inverse model matrix.
    var invModel: float4x4
  }

  // View used by the renderer.
  private let view: UIView

  // Layer attached to the view.
  private let layer: CAMetalLayer

  // Semaphore used to synchronise frames.
  private let sema: dispatch_semaphore_t

  // Metal state.
  internal let device: MTLDevice
  internal let queue: MTLCommandQueue
  internal let library: MTLLibrary

  // Buffer for view + projection matrix.
  internal var paramBuffer: MTLBuffer!
  
  // Size of the view.
  internal let width: Int
  internal let height: Int

  // Projection & view matrix from pose.
  internal var projMat = float4x4()
  internal var viewMat = float4x4()
  
  
  /**
   Initializes the core renderer.
   */
  init(view: UIView) throws {

    // Create a semaphore to sync frames.
    sema = dispatch_semaphore_create(1)

    // Creat the device and load the shaders.
    // Failure to create these is unrecoverable, so the app is killed.
    device = MTLCreateSystemDefaultDevice()!
    library = device.newDefaultLibrary()!
    queue = device.newCommandQueue()

    // Save a reference to the view.
    self.view = view
    self.width = Int(view.frame.size.width)
    self.height = Int(view.frame.size.height)
    
    // Set up the layer & the view.
    layer = CAMetalLayer()
    layer.device = device
    layer.pixelFormat = .BGRA8Unorm
    layer.framebufferOnly = true
    layer.frame = view.layer.frame
    view.layer.sublayers = nil
    view.layer.addSublayer(layer)

    // Set up the parameter buffer.
    paramBuffer = device.newBufferWithLength(
        sizeof(ARCameraParameters),
        options: MTLResourceOptions()
    )
    paramBuffer.label = "Parameters"
  }

  /**
   Updates the pose of the camera.
   */
  func updatePose(pose: ARPose) {
    
    // Model (identity).
    let modelMat = float4x4([
      float4( 1,  0,  0,  0),
      float4( 0,  1,  0,  0),
      float4( 0,  0,  1,  0),
      float4( 0,  0,  0,  1)
    ])
    
    self.projMat = pose.projMat
    self.viewMat = pose.viewMat
    
    let params = UnsafeMutablePointer<ARCameraParameters>(paramBuffer.contents())
    params.memory.proj      = pose.projMat
    params.memory.invProj   = pose.projMat.inverse
    params.memory.view      = pose.viewMat
    params.memory.normView  = pose.viewMat.inverse.transpose
    params.memory.invView   = pose.viewMat.inverse
    params.memory.model     = modelMat
    params.memory.normModel = modelMat.inverse.transpose
    params.memory.invModel  = modelMat.inverse
  }

  /**
   Renders a single frame.
   */
  func renderFrame() {
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    autoreleasepool {
      // Ensure the layer has a drawable texture.
      guard let drawable = layer.nextDrawable() else {
        dispatch_semaphore_signal(sema)
        return
      }

      // Create a command buffer & add up the semaphore on finish.
      let buffer = queue.commandBuffer()
      buffer.addCompletedHandler() {
        (MTLCommandBuffer) in dispatch_semaphore_signal(self.sema)
      }

      // Render the scene.
      onRenderFrame(drawable.texture, buffer: buffer)

      // Commit the buffer.
      buffer.presentDrawable(drawable)
      buffer.commit()
    }
  }

  /**
   Render a scene.
   */
  func onRenderFrame(target: MTLTexture, buffer: MTLCommandBuffer) {
  }
}
