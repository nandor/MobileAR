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
}


/**
 Per-object parameters.
 */
struct ARObjectParameters {
  /// Model matrix.
  var model: float4x4
  /// Normal matrix for model.
  var normModel: float4x4
  /// Inverse model matrix.
  var invModel: float4x4
}


/**
 Buffer to hold data required for a single frame.
 */
class ARRenderBuffer {
  // Semaphore that ensures that thread asking to render waits
  // until the last frame was rendered.
  private let sema: dispatch_semaphore_t
  
  // Common buffer for the MVP matrix and variations.
  internal let poseBuffer: MTLBuffer!
  
  // Camera matrices.
  internal var viewMat = float4x4()
  internal var projMat = float4x4()
  
  /**
   Initializes the rendering buffer.
   */
  required init(device: MTLDevice) {
    
    // Queue up. Made in the UK.
    sema = dispatch_semaphore_create(1)
    
    // Buffer required by most views to hold camera params.
    poseBuffer = device.newBufferWithLength(
        sizeof(ARCameraParameters),
        options: MTLResourceOptions()
    )
    poseBuffer.label = "PoseParameterBuffer"
  }
}


/**
 Class that handles rendering using Metal.
 */
class ARRenderer<Buffer: ARRenderBuffer> {
  
  // View used by the renderer.
  private let view: UIView

  // Layer attached to the view.
  private let layer: CAMetalLayer

  // Metal state.
  internal let device: MTLDevice
  internal let queue: MTLCommandQueue
  internal let library: MTLLibrary

  // Buffers for double/triple buffering.
  internal var paramBuffers: [Buffer]!
  
  // Index of the current buffer.
  internal var current: Int = 0
  
  // Current pose.
  internal var pose: ARPose?

  // Size of the view.
  internal let width: Int
  internal let height: Int
  
  // Current drawable, fetched lazily to ensure that the first time it is called,
  // it is actually used in order to block as late as possible.
  private var currentDrawable: CAMetalDrawable?
  internal var drawable: CAMetalDrawable {
    get {
      if let drawable = currentDrawable {
        return drawable
      } else {
        currentDrawable = layer.nextDrawable()
        return currentDrawable!
      }
    }
  }
  
  /**
   Initializes the core renderer.
   */
  init(view: UIView, buffers: Int) throws {
  
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
    
    // Initialize the buffers storing per-frame arguments.
    paramBuffers = (0..<buffers).map { (_) in Buffer(device: self.device) }
  }

  /**
   Updates the pose of the camera.
   */
  func updatePose(pose: ARPose) {
    self.pose = pose
  }

  /**
   Renders a single frame.
   */
  func renderFrame() {
    // Fetch the next buffer.
    current = (current + 1) % paramBuffers.count
    let params = paramBuffers[current]
    
    // Make sure the buffer is ready to be used.
    dispatch_semaphore_wait(params.sema, DISPATCH_TIME_FOREVER);
    autoreleasepool {
      
      // Fill in the param buffer parameters.
      if let pose = pose {
        params.viewMat = pose.viewMat
        params.projMat = pose.projMat
        
        // Fun stuff. The buffer is mapped & filled.
        let data = UnsafeMutablePointer<ARCameraParameters>(params.poseBuffer.contents())
        data.memory.proj      = pose.projMat
        data.memory.invProj   = pose.projMat.inverse
        data.memory.view      = pose.viewMat
        data.memory.normView  = pose.viewMat.inverse.transpose
        data.memory.invView   = pose.viewMat.inverse
      }
      
      // Create a command buffer & add up the semaphore on finish.
      let buffer = queue.commandBuffer()
      buffer.addCompletedHandler() {
        (_) in dispatch_semaphore_signal(params.sema)
      }
      
      // Render the scene.
      onRenderFrame(buffer, params: params)

      // Commit the buffer.
      buffer.presentDrawable(drawable)
      buffer.commit()
      
      // Clear the reference to the current drawable.
      currentDrawable = nil
    }
  }
  
  /**
   Render a scene.
   */
  func onRenderFrame(
      buffer: MTLCommandBuffer,
      params: Buffer)
  {
  }
}
