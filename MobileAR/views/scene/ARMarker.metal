// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include <metal_stdlib>
#include <metal_texture>

#include "ARParams.h"

using namespace metal;


/**
 Sampling distance.
 */
constant float EPS = 0.5;



/**
 Finds the coordinate of a UV point.
 */
static float2 interpolate(constant float4 *in, float2 uv) {

  // Interpolate edges.
  const float2 e0 = in[2].xy * uv.x + in[0].xy * (1 - uv.x);
  const float2 e1 = in[1].xy * uv.x + in[3].xy * (1 - uv.x);

  // Interpolate between edge points.
  return (e1 * uv.y + e0 * (1 - uv.y)) / CAMERA_SIZE;
}

/**
 Structure passing the UV & position to the fragment shader.
 */
struct ARMarkerInOut {
  /// Clip Space Position.
  float4 position [[ position ]];
  /// UV coordinate.
  float2 uv       [[ user(uv) ]];
};


/**
 Vertex shader that draws a quad over the entire screen.
 */
vertex ARMarkerInOut markerVert(
    constant float4*         in     [[ buffer(0) ]],
    uint                     id     [[ vertex_id ]])
{
  // Find the clip space coordinate of the marker.
  const float2 x = 2.0 * in[id].xy / CAMERA_SIZE - 1.0;
  return { { x.x, -x.y, 0, 1 }, in[id].zw };
}


/**
 Fragment shader for the video background.
 */
fragment half4 markerFrag(
    ARMarkerInOut           p             [[ stage_in   ]],
    constant float4*        in            [[ buffer(0)  ]],
    texture2d<half>         texBackground [[ texture(0) ]])
{
  constexpr sampler texSampler(address::clamp_to_edge, filter::linear);

  // Find 4 coordinates along the edges.
  const float2 uv00 = interpolate(in, {    p.uv.x, 0.0 - EPS });
  const float2 uv01 = interpolate(in, {    p.uv.x, 1.0 + EPS });
  const float2 uv10 = interpolate(in, { 0.0 - EPS,    p.uv.y });
  const float2 uv11 = interpolate(in, { 1.0 + EPS,    p.uv.y });

  // Sample those coordinates.
  const half4 tex00 = texBackground.sample(texSampler, uv00);
  const half4 tex01 = texBackground.sample(texSampler, uv01);
  const half4 tex10 = texBackground.sample(texSampler, uv10);
  const half4 tex11 = texBackground.sample(texSampler, uv11);

  // Interpolate those coordinates.
  const half4 e0 = tex01 * p.uv.y + tex00 * (1.0 - p.uv.y);
  const half4 e1 = tex11 * p.uv.x + tex10 * (1.0 - p.uv.x);

  // Mix them.
  return (e0 + e1) / 2;
}

