// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include <metal_texture>
using namespace metal;


/**
 Structure connecting the vertex shader to the fragment shader.
 */
struct VertexInOut
{
  float4 position [[position]];
  float2 uv       [[user(texturecoord)]];
};


/**
 Vertex shader.
 */
vertex VertexInOut testVertex(
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
 Fragment shader.
 */
fragment half4 testFragment(
    VertexInOut     inFrag [[ stage_in ]],
    texture2d<half> video  [[ texture(0) ]])
{
  constexpr sampler videoSampler(address::clamp_to_edge, filter::linear);
  return video.sample(videoSampler, inFrag.uv);
}
