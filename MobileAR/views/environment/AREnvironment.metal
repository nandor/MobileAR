// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include <metal_texture>
#include <metal_matrix>
using namespace metal;


/**
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
  packed_float3 vert;
  /// Texture coordinate.
  packed_float2 uv;
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
    constant ARSphereIn* in     [[ buffer(0) ]],
    constant ARParams&   params [[ buffer(1) ]],
    uint                 id     [[ vertex_id ]])
{
  float3 vert = float3(in[id].vert);
  float2 uv = float2(in[id].uv);

  return {
      params.proj * params.view * float4(vert.x, vert.y, vert.z, 1.0f),
      uv
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

