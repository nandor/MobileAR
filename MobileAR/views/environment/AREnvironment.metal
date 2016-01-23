// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include <metal_texture>
#include <metal_matrix>
using namespace metal;


/**git@github.com:nandor/MobileAR.git
 Parameters passed to the environment shader.
 */
struct ARParams {
  /// Perspective projection matrix.
  float4x4 proj;
  /// View matrix.
  float4x4 view;
};


/**
 Vertex shader input.
 */
struct ARSphereIn {
  /// Vertex position.
  float2 vert;
};


/**
 Video vertex shader to fragment shader.
 */
struct ARSphereInOut {
  float4 position [[ position ]];
  float2 uv       [[ user(texturecoord) ]];
};


/**
 Vertex shader for the video background.
 */
vertex ARSphereInOut sphereVert(
    constant ARSphereIn* inPosition [[ buffer(0) ]],
    uint                 id         [[ vertex_id ]])
{
  float2 uv = (inPosition[id].vert + 1.0) / 2.0;
  return {
    { inPosition[id].vert.x, inPosition[id].vert.y, 0.0, 1.0 },
    { uv.x, 1.0 - uv.y },
  };
}


/**
 Fragment shader for the video background.
 */
fragment half4 sphereFrag(
    ARSphereInOut   inFrag [[ stage_in ]],
    texture2d<half> map    [[ texture(0) ]])
{
  constexpr sampler texSampler(address::clamp_to_edge, filter::linear);
  return map.sample(texSampler, inFrag.uv);
}

