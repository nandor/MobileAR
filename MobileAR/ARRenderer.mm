// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <simd/simd.h>
#import <Metal/Metal.h>

#import "ARRenderer.h"

constexpr size_t kCommandBuffers = 3;

@implementation ARRenderer
{
  // Inflight command buffers.
  dispatch_semaphore_t commandSemaphore;
  id <MTLBuffer> commandBuffers[kCommandBuffers];
  
  // Metal renderer state.
  id <MTLDevice> device;
  id <MTLCommandQueue> commandQueue;
  id <MTLLibrary> defaultLibrary;
  id <MTLRenderPipelineState> pipelineState;
  id <MTLDepthStencilState> depthState;
  id <MTLBuffer> vertexBuffer;
  
  // Camera parameters.
  simd::float3x3 cameraMatrix;
  simd::float4 distCoeffs;
}

@end
