// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include <metal_graphics>
#include <metal_matrix>
#include <metal_stdlib>
#include <metal_texture>

#include "ARParams.h"

using namespace metal;

/**
 A digit is wrong.
 */
constant float PI = 3.1415926535897932384626433833795;

/**
 Number of regions to split the sphere into.
 */
constant int SPLIT = 9;


/**
 Vertex shader to fragment shader.
 */
struct ARSphereInOut {
  float3 vert     [[ user(world) ]];
  float4 position [[ position ]];
};



/**
 Computes the intensity of a line, based on the distance from it.
 
 This is used to draw antialiased lines over the environment map.
 */
template<typename T>
static inline T alpha(T d, T w) {
  return min(max(smoothstep(w - fwidth(d), w + fwidth(d), d), T(0)), T(1));
}



/**
 Vertex shader for the sphere
 */
vertex ARSphereInOut sphereVert(
    constant packed_float3*  in     [[ buffer(0) ]],
    constant ARParams&       params [[ buffer(1) ]],
    uint                     id     [[ vertex_id ]])
{
  float3 vert = float3(in[id]);
  return {
      vert,
      params.proj * params.view * float4(vert.x, vert.y, vert.z, 1.0f)
  };
}


/**
 Fragment shader for the video background.
 */
fragment float4 sphereFrag(
    ARSphereInOut   in  [[ stage_in ]],
    texture2d<half> map [[ texture(0) ]])
{
  constexpr sampler texSampler(address::repeat, filter::linear);
  
  // Get the UV coordinate by converting cartesian to spherical.
  float r = length(in.vert);
  float u = (atan2(in.vert.y, in.vert.x) - PI / 2) / (2 * PI);
  float v = 1.0 - acos(-in.vert.z / r) / PI;
  float2 uv = { u, v };
  
  // Compute contributions from guidelines.
  float2 a30 = fract(uv * SPLIT);
  a30 = alpha(min(a30, 1.0 - a30), { 0.005, 0.010 });
  float2 a10 = fract(uv * SPLIT * 3);
  a10 = alpha(min(a10, 1.0 - a10), { 0.010, 0.020 });
  float grenwich = alpha(abs(u - 0.0), 0.001);
  float equator = alpha(abs(v - 0.5), 0.002);
  
  // Do not draw lines on the top and at the bottom of the sphere.
  if (v < 1.0 / SPLIT || v > 1.0 * (SPLIT - 1) / SPLIT) {
    a10.x = a10.y = a30.x = 1.0;
    grenwich = 1.0;
    equator = 1.0;
    if (v < 0.01 || v > 0.99) {
      a30.y = 1.0;
    }
  }
  
  // Mix the colours.
  float4 colour = (float4)map.sample(texSampler, {u, v});
  colour = mix({0.7, 0.7, 0.7, 1}, colour, a10.x);
  colour = mix({0.7, 0.7, 0.7, 1}, colour, a10.y);
  colour = mix({0.9, 0.9, 0.9, 1}, colour, a30.x);
  colour = mix({0.9, 0.9, 0.9, 1}, colour, a30.y);
  colour = mix({0.0, 0.0, 1.0, 1}, colour, equator);
  colour = mix({1.0, 0.0, 0.0, 1}, colour, grenwich);
  return colour;
}
