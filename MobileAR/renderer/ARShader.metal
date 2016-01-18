// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include <metal_texture>
#include <metal_matrix>

#include "ARParams.h"

using namespace metal;


/**
 Video vertex shader to fragment shader.
 */
struct ARVideoInOut {
  float4 position [[position]];
  float2 uv       [[user(texturecoord)]];
};


/**
 Vertex shader for the video background.
 */
vertex ARVideoInOut videoVert(
    constant float2* inPosition [[ buffer(0) ]],
    uint             id         [[ vertex_id ]])
{
  float2 uv = (inPosition[id] + 1.0) / 2.0;
  return {
    { inPosition[id].x, inPosition[id].y, 0.0, 1.0 },
    { uv.x, 1.0 - uv.y },
  };
}


/**
 Fragment shader for the video background.
 */
fragment half4 videoFrag(
    ARVideoInOut    inFrag [[ stage_in ]],
    texture2d<half> video  [[ texture(0) ]])
{
  constexpr sampler videoSampler(address::clamp_to_edge, filter::linear);
  return video.sample(videoSampler, inFrag.uv);
}


/**
 Object vertex shader to fragment shader.
 */
struct ARObjectInOut {
  float4 position [[position]];
  float3 normal   [[user(normal)]];
};

/**
 A vertex of the AR object.
 */
struct ARObjectIn {
  float4 position;
  float4 normal;
};


/**
 Vertex shader for the AR object.
 */
vertex ARObjectInOut objectVert(
    constant ARObjectIn* in         [[ buffer(0) ]],
    constant ARParams&   params     [[ buffer(1) ]],
    uint                 id         [[ vertex_id ]])
{
  return { params.K * params.P * in[id].position, in[id].normal.xyz };
}


/**
 Fragment shader for the AR object.
 */
fragment half4 objectFrag(
    ARObjectInOut   in     [[ stage_in ]],
    texture2d<half> video  [[ texture(0) ]])
{
  half3 normal = (half3)in.normal.xyz;
  normal = (normal + 1.0f) / 2.0f;
  return {normal.x, normal.y, normal.z, 1.0f};
}

