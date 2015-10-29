// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <simd/simd.h>
#import <Metal/Metal.h>

#import "ARRenderer.h"


static const float kQuadVertexData[] =
{
  -1.0f, -1.0f,
  -1.0f,  1.0f,
   1.0f,  1.0f,
  
  -1.0f, -1.0f,
   1.0f,  1.0f,
   1.0f, -1.0f,
};


@implementation ARRenderer
{
  // Inflight command buffers for triple buffering.
  dispatch_semaphore_t commandSemaphore;
  
  // Metal renderer state.
  id <MTLDevice> device;
  id <MTLCommandQueue> commandQueue;
  id <MTLLibrary> library;
  id <MTLRenderPipelineState> pipelineState;
  id <MTLDepthStencilState> depthState;
  id <MTLBuffer> vertexBuffer;
  
  // Camera parameters.
  simd::float3x3 cameraMatrix;
  simd::float4 distCoeffs;
  
  // View controller.
  UIView *view;
  CAMetalLayer *layer;
  
  // Render timer.
  CADisplayLink *timer;
}


/**
 Creates a new renderer.
 */
-(id)initWithView:(UIView*)uiView
{
  if (!(self = [super init])) {
    return nil;
  }
  
  // Save the view.
  view = uiView;
  
  // Initialize Metal.
  device = MTLCreateSystemDefaultDevice();
  layer = (CAMetalLayer*)view.layer;
  layer.device = device;
  layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
  layer.framebufferOnly = YES;

  if (!(commandQueue = [device newCommandQueue])) {
    NSLog(@"Cannot create command queue.");
    return nil;
  }
  if (!(library = [device newDefaultLibrary])) {
    NSLog(@"Cannot create default library.");
    return nil;
  }
  if (![self createVertexBuffer]) {
    NSLog(@"Cannot create vertex buffer.");
    return nil;
  }
  if (![self createPipelineState]) {
    NSLog(@"Cannot create pipeline state.");
    return nil;
  }
  if (![self createDepthState]) {
    NSLog(@"Cannot create depth state.");
    return nil;
  }
  
  // Triple buffering.
  commandSemaphore = dispatch_semaphore_create(3);
  
  return self;
}


/**
 Renders a frame.
 */
-(void)render
{
  @autoreleasepool {
    dispatch_semaphore_wait(commandSemaphore, DISPATCH_TIME_FOREVER);
    
    id <MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    {
      auto drawable = [layer nextDrawable];
     
      // Create a render pass descriptor.
      auto renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
      auto colorAttachment = renderPassDescriptor.colorAttachments[0];
      colorAttachment.texture = drawable.texture;
      colorAttachment.loadAction = MTLLoadActionClear;
      colorAttachment.clearColor = MTLClearColorMake(0.0f, 0.0f, 0.0f, 0.0f);
      colorAttachment.storeAction = MTLStoreActionStore;
      
      // create a render command encoder so we can render into something
      auto renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
      [renderEncoder setCullMode:MTLCullModeBack];
      [renderEncoder setDepthStencilState:depthState];
      [renderEncoder setRenderPipelineState:pipelineState];
      [renderEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:0 ];
      [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
      [renderEncoder endEncoding];
      
      // Draw stuff on the view & release the drawable.
      [commandBuffer presentDrawable:drawable];
      drawable = nil;
    }

    // Commit the frame & signal on completion.
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
      dispatch_semaphore_signal(commandSemaphore);
    }];
    [commandBuffer commit];
  }
}


/**
 Starts rendering.
 */
- (void)start
{
  timer = [[UIScreen mainScreen] displayLinkWithTarget:self selector:@selector(render)];
  timer.frameInterval = 1;
  [timer addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
}

/**
 Stops rendering.
 */
- (void)stop
{
  [timer invalidate];
  timer = nil;
}


/**
 Creates the pipeline state.
 */
- (BOOL)createPipelineState
{
  // Fetch the vertex & fragment shaders.
  id <MTLFunction> fragmentProgram = [library newFunctionWithName:@"testFragment"];
  if (!fragmentProgram) {
    NSLog(@"Cannot load fragment shader 'testFragment'.");
    return NO;
  }
  id <MTLFunction> vertexProgram = [library newFunctionWithName:@"testVertex"];
  if (!vertexProgram) {
    NSLog(@"Cannot load vertex shader 'testVertex'.");
    return NO;
  }
  
  // Create a pipeline state descriptor.
  auto pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
  pipelineStateDescriptor.label                           = @"TestPipeline";
  pipelineStateDescriptor.sampleCount                     = 1;
  pipelineStateDescriptor.vertexFunction                  = vertexProgram;
  pipelineStateDescriptor.fragmentFunction                = fragmentProgram;
  pipelineStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
  
  // Create the pipeline state.
  NSError *error = nil;
  pipelineState = [device
      newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
      error:&error
  ];
  if (!pipelineState) {
    NSLog(@"Cannot create pipeline state.");
    return NO;
  }
  
  return YES;
}


/**
 Initializes the depth & stencil state.
 */
- (BOOL)createDepthState
{
  auto depthStateDesc = [[MTLDepthStencilDescriptor alloc] init];
  depthStateDesc.depthCompareFunction = MTLCompareFunctionLess;
  depthStateDesc.depthWriteEnabled = YES;
  depthState = [device newDepthStencilStateWithDescriptor:depthStateDesc];
  return YES;
}

/**
 Initializes the vertex buffer.
 */
- (BOOL)createVertexBuffer
{
  vertexBuffer = [device
     newBufferWithBytes: kQuadVertexData
     length: sizeof(kQuadVertexData)
     options: MTLResourceOptionCPUCacheModeDefault
  ];
  vertexBuffer.label = @"Quad Vertices";
  return YES;
}

@end
