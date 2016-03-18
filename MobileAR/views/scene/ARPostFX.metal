// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include <metal_stdlib>
#include <metal_texture>

#include "ARParams.h"

using namespace metal;



/**
 Vertex shader that draws a quad over the entire screen.
 */
vertex ARQuadInOut fullscreen(
    constant packed_float2*  in     [[ buffer(0) ]],
    uint                     id     [[ vertex_id ]])
{
  const float2 vert = float2(in[id]);

  return {
    { (vert.x + 1.0) * 0.5, (1.0 - vert.y) * 0.5 },
    { vert.x, vert.y, 0.0, 1.0 }
  };
}


/**
 Fragment shader for the video background.
 */
fragment float4 background(
    ARQuadInOut     in            [[ stage_in ]],
    texture2d<half> texBackground [[ texture(0) ]],
    texture2d<float> texAO         [[ texture(1) ]])
{
  constexpr sampler texSampler(address::clamp_to_edge, filter::linear);

  const half4 background = texBackground.sample(texSampler, in.uv);
  const float ao = texAO.sample(texSampler, in.uv).x;

  return float4(background) * ao;
}

