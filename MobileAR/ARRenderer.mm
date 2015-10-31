// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <simd/simd.h>
#import <Metal/Metal.h>

#import "ARParams.h"
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

static const float kCubeVertexData[] =
{
  -1.0f, -1.0f, -1.0f, 1.0f, -1.0f,  0.0f,  0.0f,  0.0f,
  -1.0f, -1.0f,  1.0f, 1.0f, -1.0f,  0.0f,  0.0f,  0.0f,
  -1.0f,  1.0f,  1.0f, 1.0f, -1.0f,  0.0f,  0.0f,  0.0f,
  -1.0f, -1.0f, -1.0f, 1.0f, -1.0f,  0.0f,  0.0f,  0.0f,
  -1.0f,  1.0f,  1.0f, 1.0f, -1.0f,  0.0f,  0.0f,  0.0f,
  -1.0f,  1.0f, -1.0f, 1.0f, -1.0f,  0.0f,  0.0f,  0.0f,
   1.0f, -1.0f, -1.0f, 1.0f,  1.0f,  0.0f,  0.0f,  0.0f,
   1.0f, -1.0f,  1.0f, 1.0f,  1.0f,  0.0f,  0.0f,  0.0f,
   1.0f,  1.0f,  1.0f, 1.0f,  1.0f,  0.0f,  0.0f,  0.0f,
   1.0f, -1.0f, -1.0f, 1.0f,  1.0f,  0.0f,  0.0f,  0.0f,
   1.0f,  1.0f,  1.0f, 1.0f,  1.0f,  0.0f,  0.0f,  0.0f,
   1.0f,  1.0f, -1.0f, 1.0f,  1.0f,  0.0f,  0.0f,  0.0f,
  -1.0f, -1.0f, -1.0f, 1.0f,  0.0f, -1.0f,  0.0f,  0.0f,
  -1.0f, -1.0f,  1.0f, 1.0f,  0.0f, -1.0f,  0.0f,  0.0f,
   1.0f, -1.0f,  1.0f, 1.0f,  0.0f, -1.0f,  0.0f,  0.0f,
  -1.0f, -1.0f, -1.0f, 1.0f,  0.0f, -1.0f,  0.0f,  0.0f,
   1.0f, -1.0f,  1.0f, 1.0f,  0.0f, -1.0f,  0.0f,  0.0f,
   1.0f, -1.0f, -1.0f, 1.0f,  0.0f, -1.0f,  0.0f,  0.0f,
  -1.0f,  1.0f, -1.0f, 1.0f,  0.0f,  1.0f,  0.0f,  0.0f,
  -1.0f,  1.0f,  1.0f, 1.0f,  0.0f,  1.0f,  0.0f,  0.0f,
   1.0f,  1.0f,  1.0f, 1.0f,  0.0f,  1.0f,  0.0f,  0.0f,
  -1.0f,  1.0f, -1.0f, 1.0f,  0.0f,  1.0f,  0.0f,  0.0f,
   1.0f,  1.0f,  1.0f, 1.0f,  0.0f,  1.0f,  0.0f,  0.0f,
   1.0f,  1.0f, -1.0f, 1.0f,  0.0f,  1.0f,  0.0f,  0.0f,
  -1.0f, -1.0f, -1.0f, 1.0f,  0.0f,  0.0f, -1.0f,  0.0f,
  -1.0f,  1.0f, -1.0f, 1.0f,  0.0f,  0.0f, -1.0f,  0.0f,
   1.0f,  1.0f, -1.0f, 1.0f,  0.0f,  0.0f, -1.0f,  0.0f,
  -1.0f, -1.0f, -1.0f, 1.0f,  0.0f,  0.0f, -1.0f,  0.0f,
   1.0f,  1.0f, -1.0f, 1.0f,  0.0f,  0.0f, -1.0f,  0.0f,
   1.0f, -1.0f, -1.0f, 1.0f,  0.0f,  0.0f, -1.0f,  0.0f,
  -1.0f, -1.0f,  1.0f, 1.0f,  0.0f,  0.0f,  1.0f,  0.0f,
  -1.0f,  1.0f,  1.0f, 1.0f,  0.0f,  0.0f,  1.0f,  0.0f,
   1.0f,  1.0f,  1.0f, 1.0f,  0.0f,  0.0f,  1.0f,  0.0f,
  -1.0f, -1.0f,  1.0f, 1.0f,  0.0f,  0.0f,  1.0f,  0.0f,
   1.0f,  1.0f,  1.0f, 1.0f,  0.0f,  0.0f,  1.0f,  0.0f,
   1.0f, -1.0f,  1.0f, 1.0f,  0.0f,  0.0f,  1.0f,  0.0f,
};

@implementation ARRenderer
{
  // Inflight command buffers for triple buffering.
  dispatch_semaphore_t frameWait;

  // Metal renderer state.
  id<MTLDevice> device;
  id<MTLCommandQueue> commandQueue;
  id<MTLLibrary> library;

  id<MTLDepthStencilState> videoDepthState;
  id<MTLDepthStencilState> objectDepthState;
  id<MTLRenderPipelineState> videoState;
  id<MTLRenderPipelineState> objectState;
  id<MTLTexture> videoTexture;
  id<MTLBuffer> quadBuffer;
  id<MTLBuffer> cubeBuffer;
  id<MTLBuffer> paramBuffer;

  // View & layer.
  CAMetalLayer *layer;
  UIView *view;

  // Render timer.
  CADisplayLink *timer;

  // Copy of the image being displayed.
  cv::Mat videoFrame;
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

  frameWait = dispatch_semaphore_create(1);
  return self;
}


/**
 Changes the video frame.
 */
- (void)update:(cv::Mat)texture K:(cv::Mat)K r:(cv::Mat)r t:(cv::Mat)t d:(cv::Mat)d
{
  ARParams *params = static_cast<ARParams*>([paramBuffer contents]);

  // Intrinsic parameters.
  {
    float a = K.at<float>(0, 0);
    float b = K.at<float>(1, 1);
    float cx = K.at<float>(0, 2);
    float cy = K.at<float>(1, 2);
    float f = 1000.0f;
    float n = 0.1f;
    
    params->K = simd::float4x4{
        simd::float4{ a / cx,   0.0f,                 0.0f,  0.0f },
        simd::float4{   0.0f, b / cy,                 0.0f,  0.0f },
        simd::float4{   0.0f,   0.0f,   -(f + n) / (f - n), -1.0f },
        simd::float4{   0.0f,   0.0f, -2 * f * n / (f - n),  0.0f },
    };
  }
  // Extrinsic parameters.
  {
    cv::Mat R(3, 3, CV_32F);
    cv::Rodrigues(r, R);
    R.convertTo(R, CV_32F);
    
    params->P = simd::float4x4{
      simd::float4{
          R.at<float>(0, 0),
          R.at<float>(1, 0),
          R.at<float>(2, 0),
          0.0f
      },
      simd::float4{
          R.at<float>(0, 1),
          R.at<float>(1, 1),
          R.at<float>(2, 1),
          0.0f
      },
      simd::float4{
          R.at<float>(0, 2),
          R.at<float>(1, 2),
          R.at<float>(2, 2),
          0.0f
      },
      simd::float4{
          t.at<float>(0, 0),
          t.at<float>(1, 0),
          t.at<float>(2, 0),
          1.0f
      },
    };
    
    params->P = simd::float4x4{
        simd::float4{1.0f,  0.0f,  0.0f,  0.0f},
        simd::float4{0.0f, -1.0f,  0.0f,  0.0f},
        simd::float4{0.0f,  0.0f, -1.0f,  0.0f},
        simd::float4{0.0f,  0.0f,  0.0f,  1.0f},
    } * params->P;
  }
  
  // Radial + tangential distortion.
  {
    params->dist = simd::float4{
      0.0f, 0.0f, 0.0f, 0.0f
    };
  }

  // Upload video frame.
  videoFrame = texture.clone();
  [videoTexture
      replaceRegion: MTLRegionMake2D(0, 0, videoFrame.cols, videoFrame.rows)
      mipmapLevel: 0
      withBytes: videoFrame.data
      bytesPerRow: videoFrame.step[0]
   ];
}


/**
 Renders a frame.
 */
-(void)render
{
  dispatch_semaphore_wait(frameWait, DISPATCH_TIME_FOREVER);
  @autoreleasepool {
    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];

    // Ensure the drawable has a renderable texture.
    auto drawable = [layer nextDrawable];
    if (drawable.texture) {
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

      // Draw stuff on the view & release the drawable.
      [commandBuffer presentDrawable:drawable];
      drawable = nil;
    }

    // Commit the frame & signal on completion.
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
      dispatch_semaphore_signal(frameWait);
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


/**
 Initializes the video texture
 */
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


/**
 Initializes the constant parameter buffer.
 */
- (id<MTLBuffer>)createParamBuffer
{
  auto buffer = [device
      newBufferWithLength: sizeof(ARParams)
      options: 0
  ];
  if (!buffer) {
    return nil;
  }
  buffer.label = @"Param buffer";
  return buffer;
}

@end
