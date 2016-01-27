// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include <metal_graphics>
#include <metal_matrix>
#include <metal_stdlib>
#include <metal_texture>

using namespace metal;


/**
 Input to the vertex shader.
 */
struct ARQuadIn {
  packed_float3 vert;
  packed_float3 norm;
  packed_float2 uv;
};


/**
 Vertex shader to fragment shader.
 */
struct ARQuadInOut {
  float2 uv       [[ user(uv) ]];
  float4 position [[ position ]];
};



/**
 Vertex shader that draws a quad over the entire screen.
 */
vertex ARQuadInOut fullscreen(
    constant packed_float2*  in     [[ buffer(0) ]],
    uint                     id     [[ vertex_id ]])
{
  float2 vert = float2(in[id]);
  
  return {
    { (vert.x + 1.0) * 0.5, (1.0 - vert.y) * 0.5 },
    { vert.x, vert.y, 0.0, 1.0 }
  };
}


/**
 Fragment shader for the video background.
 */
fragment float4 background(
    ARQuadInOut     in         [[ stage_in ]],
    texture2d<half> background [[ texture(0) ]])
{
  constexpr sampler backgroundSampler(address::clamp_to_edge, filter::linear);
  return float4(background.sample(backgroundSampler, in.uv));
}
