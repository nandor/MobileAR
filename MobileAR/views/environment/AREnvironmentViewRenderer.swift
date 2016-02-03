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
 Renders an environment map over on a sphere around the origin.
 */
class AREnvironmentViewRenderer : ARRenderer {

  // Spherical texture to be displayed.
  private var texture: MTLTexture!

  // Depth buffer state.
  private var depthState: MTLDepthStencilState!

  // Renderer state.
  private var renderState: MTLRenderPipelineState!

  // Vertex buffer for the spherical mesh.
  private var sphereVBO: MTLBuffer!

  // Index buffer for the spherical mesh.
  private var sphereIBO: MTLBuffer!


  /**
   Initializes the environment renderer.
   */
  init(view: UIView, environment: AREnvironment) throws {
    try super.init(view: view)

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

        vbo[idx + 0] = Float(cos(phi) * sin(theta))
        vbo[idx + 1] = Float(cos(phi) * cos(theta))
        vbo[idx + 2] = -Float(sin(phi))
      }
    }
    sphereVBO = device.newBufferWithBytes(
        vbo,
        length: sizeofValue(vbo[0]) * vbo.count,
        options: MTLResourceOptions()
    )

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
  }

  /**
   Renders the environment.
   */
  override func onRenderFrame(target: MTLTexture, buffer: MTLCommandBuffer) {

    // Create the render command descriptor.
    let renderDesc = MTLRenderPassDescriptor()
    let color = renderDesc.colorAttachments[0]
    color.texture = target
    color.loadAction = .DontCare
    color.storeAction = .Store

    let encoder = buffer.renderCommandEncoderWithDescriptor(renderDesc)

    // Render the sphere.
    encoder.setDepthStencilState(depthState)
    encoder.setRenderPipelineState(renderState)
    encoder.setVertexBuffer(sphereVBO, offset: 0, atIndex: 0)
    encoder.setVertexBuffer(paramBuffer, offset: 0, atIndex: 1)
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
