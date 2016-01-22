// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import Metal
import QuartzCore


/**
 Enumerations of things that can go wrong with the renderer.
 */
enum ARRendererException : ErrorType {
  case DeviceError
  case LibraryError
}


/**
 Class that handles rendering using Metal.
 */
class ARRenderer : NSObject {

  // Layer attached to the view.
  private let layer: CAMetalLayer

  // Semaphore used to synchronise frames.
  private let sema: dispatch_semaphore_t

  // Metal state.
  internal let device: MTLDevice
  internal let queue: MTLCommandQueue
  internal let library: MTLLibrary

/*
  id<MTLDepthStencilState> videoDepthState;
  id<MTLDepthStencilState> objectDepthState;
  id<MTLRenderPipelineState> videoState;
  id<MTLRenderPipelineState> objectState;
  id<MTLTexture> videoTexture;
  id<MTLBuffer> quadBuffer;
  id<MTLBuffer> cubeBuffer;
  id<MTLBuffer> paramBuffer;
}
*/
  init(view: UIView) throws {

    // Create a semaphore to sync frames.
    sema = dispatch_semaphore_create(1)

    // Creat the device and load the shaders.
    // Failure to create these is unrecoverable, so the app is killed.
    device = MTLCreateSystemDefaultDevice()!
    library = device.newDefaultLibrary()!
    queue = device.newCommandQueue()

    // Set up the layer & the view.
    layer = CAMetalLayer()
    layer.device = device
    layer.pixelFormat = .BGRA8Unorm
    layer.framebufferOnly = true
    layer.frame = view.layer.frame
    view.layer.addSublayer(layer)

    // Set up the quad buffer.

  }
/*
-(instancetype)initWithView:(UIView*)uiView
{
  // Initialize vertex buffers.
  {
    quadBuffer = [device
        newBufferWithBytes: kQuadVertexData
        length: sizeof(kQuadVertexData)
        options: MTLResourceOptionCPUCacheModeDefault
    ];
    if (!quadBuffer) {
      NSLog(@"Cannot create quad buffer.");
      return nil;
    }
    quadBuffer.label = @"Quad Vertex Buffer.";

    cubeBuffer = [device
        newBufferWithBytes: kCubeVertexData
        length: sizeof(kCubeVertexData)
        options: MTLResourceOptionCPUCacheModeDefault
    ];
    if (!cubeBuffer) {
      NSLog(@"Cannot create cube buffer.");
      return nil;
    }
    cubeBuffer.label = @"Cube Vertex Buffer.";
  }

  // Initializes the pipeline state.
  {
    videoState = [self createPipelineState: @"VideoState" frag: @"videoFrag" vert: @"videoVert"];
    if (!videoState) {
      NSLog(@"Cannot create video pipeline state.");
      return nil;
    }
    objectState = [self createPipelineState: @"ObjectState" frag:@"objectFrag" vert: @"objectVert"];
    if (!objectState) {
      NSLog(@"Cannot create object pipeline state.");
      return nil;
    }
  }

  // Initializes the depth buffer states.
  {
    MTLDepthStencilDescriptor *desc;

    desc = [[MTLDepthStencilDescriptor alloc] init];
    desc.depthCompareFunction = MTLCompareFunctionAlways;
    desc.depthWriteEnabled = NO;
    videoDepthState = [device newDepthStencilStateWithDescriptor:desc];
    if (!videoDepthState) {
      NSLog(@"Cannot create video depth state.");
      return nil;
    }

    desc = [[MTLDepthStencilDescriptor alloc] init];
    desc.depthCompareFunction = MTLCompareFunctionLess;
    desc.depthWriteEnabled = YES;
    objectDepthState = [device newDepthStencilStateWithDescriptor:desc];
    if (!objectDepthState) {
      NSLog(@"Cannot create object depth state.");
      return nil;
    }
  }

  if (!(videoTexture = [self createTexture])) {
    NSLog(@"Cannot create texture.");
    return nil;
  }
  if (!(paramBuffer = [self createParamBuffer])) {
    NSLog(@"Cannot create parameter buffer.");
    return nil;
  }
}

*/

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
      renderScene(buffer: buffer)

      // Commit the buffer.
      buffer.presentDrawable(drawable)
      buffer.commit()
    }
  }

  /**
   Render a scene.
   */
  func renderScene() {
  }

/*
-(void)render
{
  // Create a render pass descriptor.
  auto renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  auto colorAttachment = renderPassDescriptor.colorAttachments[0];
  colorAttachment.texture = drawable.texture;
  colorAttachment.loadAction = MTLLoadActionClear;
  colorAttachment.clearColor = MTLClearColorMake(0.0f, 0.0f, 0.0f, 0.0f);
  colorAttachment.storeAction = MTLStoreActionStore;

  // Enqueue all render calls.
  auto renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];

  // Render the background texture.
  [renderEncoder setDepthStencilState:videoDepthState];
  [renderEncoder setRenderPipelineState:videoState];
  [renderEncoder setVertexBuffer:quadBuffer offset:0 atIndex:0];
  [renderEncoder setFragmentTexture:videoTexture atIndex:0];
  [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];

  // Render the AR object.
  [renderEncoder setDepthStencilState:objectDepthState];
  [renderEncoder setRenderPipelineState:objectState];
  [renderEncoder setVertexBuffer:cubeBuffer offset:0 atIndex:0];
  [renderEncoder setVertexBuffer:paramBuffer offset:0 atIndex:1];
  [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:36];

  [renderEncoder endEncoding];
}
*/
/*
- (id<MTLRenderPipelineState>)createPipelineState:(NSString*)label
                                             frag:(NSString*)frag
                                             vert:(NSString*)vert
{
  // Fetch the vertex & fragment shaders.
  id <MTLFunction> fragmentProgram = [library newFunctionWithName:frag];
  if (!fragmentProgram) {
    NSLog(@"Cannot load fragment shader '%@'.", frag);
    return nil;
  }
  id <MTLFunction> vertexProgram = [library newFunctionWithName:vert];
  if (!vertexProgram) {
    NSLog(@"Cannot load vertex shader '%@'.", vert);
    return nil;
  }

  // Create a pipeline state descriptor.
  auto pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
  pipelineStateDescriptor.label                           = label;
  pipelineStateDescriptor.sampleCount                     = 1;
  pipelineStateDescriptor.vertexFunction                  = vertexProgram;
  pipelineStateDescriptor.fragmentFunction                = fragmentProgram;
  pipelineStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

  // Create the pipeline state.
  NSError *error = nil;
  return [device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
}

- (id<MTLTexture>)createTexture
{
  auto desc = [[MTLTextureDescriptor alloc] init];
  desc.textureType = MTLTextureType2D;
  desc.height = 360;
  desc.width = 480;
  desc.depth = 1;
  desc.pixelFormat = MTLPixelFormatBGRA8Unorm;
  desc.arrayLength = 1;
  desc.mipmapLevelCount = 1;
  return [device newTextureWithDescriptor:desc];
}

- (id<MTLBuffer>)createParamBuffer
{
  auto buffer = [device
      newBufferWithLength: 16 * sizeof(float)
      options: 0
  ];
  if (!buffer) {
    return nil;
  }
  buffer.label = @"Param buffer";
  return buffer;
}

@end

*/
  // Rectangle covering the entire screen.
  static let MESH_QUAD: [Float] = [
      -1.0, -1.0,
      -1.0,  1.0,
       1.0,  1.0,
      -1.0, -1.0,
       1.0,  1.0,
       1.0, -1.0,
  ]
}