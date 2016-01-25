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
  internal var params: MTLBuffer!

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

    // Set up the layer & the view.
    layer = CAMetalLayer()
    layer.device = device
    layer.pixelFormat = .BGRA8Unorm
    layer.framebufferOnly = true
    layer.frame = view.layer.frame
    view.layer.addSublayer(layer)

    // Set up the parameter buffer.
    params = device.newBufferWithLength(sizeof(Float) * 32, options: MTLResourceOptions())
  }

  /**
   Updates the pose of the camera.
   */
  func updatePose(rx rx: Float, ry: Float, rz: Float, tx: Float, ty: Float, tz: Float) {

    // Pitch.
    let rotX = float4x4([
        float4(+cos(rx), 0, -sin(rx), 0),
        float4(       0, 1,        0, 0),
        float4(+sin(rx), 0, +cos(rx), 0),
        float4(       0, 0,        0, 1)
    ])

    // Yaw.
    let rotY = float4x4([
        float4(+cos(ry), +sin(ry), 0, 0),
        float4(-sin(ry), +cos(ry), 0, 0),
        float4(       0,        0, 1, 0),
        float4(       0,        0, 0, 1)
    ])

    // Roll.
    let rotZ = float4x4([
        float4(1,        0,        0, 0),
        float4(0, +cos(rz), +sin(rz), 0),
        float4(0, -sin(rz), +cos(rz), 0),
        float4(0,        0,        0, 1)
    ])

    // Translation.
    let trans = float4x4([
        float4( 1,  0,  0,  0),
        float4( 0,  1,  0,  0),
        float4( 0,  0,  1,  0),
        float4(tx, ty, tz,  1)
    ])

    // Compute the view matrix.
    let viewMat = rotZ * rotX * rotY * trans

    // Compute the projection matrix.
    let aspect = Float(view.frame.width) / Float(view.frame.height)
    let tanFOV = Float(tan((45.0 / 180.0 * M_PI) / 2.0))
    let yScale = 1.0 / tanFOV
    let xScale = 1.0 / (aspect * tanFOV)
    let f: Float = 200.0
    let n: Float = 0.1
    let projMat = float4x4([
        float4(xScale,      0,                   0,  0),
        float4(     0, yScale,                   0,  0),
        float4(     0,      0,   (f + n) / (n - f), -1),
        float4(     0,      0, 2 * n * f / (n - f),  0)
    ])

    // Upload stuff to the param buffer.
    params = device.newBufferWithBytes(
        [projMat, viewMat],
        length: sizeofValue(projMat) + sizeofValue(viewMat),
        options: MTLResourceOptions()
    )
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
      renderScene(drawable.texture, buffer: buffer)

      // Commit the buffer.
      buffer.presentDrawable(drawable)
      buffer.commit()
    }
  }

  /**
   Render a scene.
   */
  func renderScene(texture: MTLTexture, buffer: MTLCommandBuffer) {
  }
}