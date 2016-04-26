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
 Light input data.
 */
struct ARLightIn {
  float4 direction;
  float4 diffuse;
};

/**
 Vertex shader to fragment shader.
 */
struct ARLightInOut {
  float3 direction [[ user(direction) ]];
  float3 vert      [[ user(world) ]];
  float4 diffuse   [[ user(diffuse) ]];
  float4 position  [[ position ]];
};


/**
 Computes the intensity of a line, based on the distance from it.
 
 This is used to draw antialiased lines over the environment map.
 */
template<typename T>
static inline T alpha(T d, T w) {
  return saturate(smoothstep(w - fwidth(d), w + fwidth(d), d));
}



/**
 Vertex shader for the sphere
 */
vertex ARSphereInOut envSphereVert(
    constant packed_float3*  in     [[ buffer(0) ]],
    constant ARCameraParams& params [[ buffer(1) ]],
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
fragment float4 envSphereFrag(
    ARSphereInOut   in  [[ stage_in ]],
    texture2d<half> map [[ texture(0) ]])
{
  constexpr sampler texSampler(address::repeat, filter::linear);
  
  // Get the UV coordinate by converting cartesian to spherical.
  float r = length(in.vert);
  float u = atan2(in.vert.y, in.vert.x) / (2 * PI);
  float v = acos(in.vert.z / r) / PI;
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


/**
 Light source quad.
 */
vertex ARLightInOut envLightVert(
    constant packed_float2*  in     [[ buffer(0) ]],
    constant ARCameraParams& params [[ buffer(1) ]],
    constant ARLightIn*      lights [[ buffer(2) ]],
    uint                     vid    [[ vertex_id ]],
    uint                     iid    [[ instance_id ]])
{
  // Unpack the vertex.
  const float3 v = float3(in[vid], 0.0);

  // View matrix from origin towards point.
  const float3 z = normalize(-lights[iid].direction.xyz);
  const float3 x = normalize(cross(z, float3(0, 0, 1)));
  const float3 y = cross(z, x);
  const float3x3 M = float3x3(x, y, z);

  // Compute the quads's corner.
  const float3 p = z + M * v;

  return {
    z,
    p,
    lights[iid].diffuse,
    params.proj * params.view * float4(p, 1)
  };
}


fragment float4 envLightFrag(
    ARLightInOut   in  [[ stage_in ]])
{
  const float angle = acos(dot(in.direction, normalize(in.vert)));
  if (angle < 0.05) {
    // Diffuse colour.
    return float4(in.diffuse.xyz, 1);
  } else if (angle < 0.052) {
    // Border.
    return float4(0, 0, 0, 1);
  } else {
    // Outside circle, transparent.
    return float4(0);
  }
}


/**
 Texture projection from a sphere.
 */
static float3 unproject(
    const float4x4 P,
    const uint2 uv,
    const uint2 dsSize,
    const uint2 imSize)
{
  // Convert the point to polar coordinates.
  const float phi = PI / 2.0f - (float(uv.y) / float(dsSize.y)) * PI;
  const float theta = (float(uv.x) / float(dsSize.x)) * PI * 2;
  const float4 vert = float4(
      cos(phi) * cos(theta),
      cos(phi) * sin(theta),
      sin(phi),
      1
  );
  
  // Project the point onto the texture.
  const float4 proj = P * vert;
  
  // Perspective division & scale to [0, 1]
  return float3(
      1.0f - proj.x / proj.z / imSize.x,
      proj.y / proj.z / imSize.y,
      proj.z
  );
}


/**
 Compute shader to project an image onto a panorama.
 */
kernel void composite(
    uint2                           pix    [[ thread_position_in_grid ]],
    texture2d<half, access::sample> src    [[ texture(0) ]],
    texture2d<half, access::write>  dst    [[ texture(1) ]],
    constant ARCompositeParams     *params [[ buffer(0) ]])
{
  constexpr sampler texSampler(address::repeat, filter::linear);
  
  // Ensure it is within bounds.
  const float3 uv = unproject(
      params->projView,
      pix,
      {dst.get_width(), dst.get_height()},
      {src.get_width(), src.get_height()}
  );
  if (uv.x < 0.0f || uv.x > 1.0f || uv.y < 0.0f || uv.y > 1.0f || uv.z > 0.0) {
    return;
  }
  
  // Sample the source image & write output.
  dst.write(src.sample(texSampler, uv.xy), pix, 0);
}


/**
 Compute shader to project an image onto a panorama, weighting it.
 */
kernel void compositeWeighted(
    uint2                            pix        [[ thread_position_in_grid ]],
    texture2d<half,  access::sample> src        [[ texture(0) ]],
    texture2d<float, access::read>   dstColour0 [[ texture(1) ]],
    texture2d<float, access::read>   dstWeight0 [[ texture(2) ]],
    texture2d<float, access::write>  dstColour1 [[ texture(3) ]],
    texture2d<float, access::write>  dstWeight1 [[ texture(4) ]],
    constant ARCompositeParams      *params     [[ buffer(0) ]])
{
  constexpr sampler texSampler(address::repeat, filter::linear);
  
  // Ensure it is within bounds.
  const float3 uv = unproject(
      params->projView,
      pix,
      {dstColour0.get_width(), dstColour0.get_height()},
      {src.get_width(), src.get_height()}
  );
  if (uv.x < 0.0f || uv.x > 1.0f || uv.y < 0.0f || uv.y > 1.0f || uv.z > 0.0) {
    return;
  }
  
  // Compute the weight.
  const float w = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  
  // Sample the source image & write output.
  const float4 colour = (float4)src.sample(texSampler, uv.xy);
  dstColour1.write(dstColour0.read(pix, 0) + w * colour, pix, 0);
  dstWeight1.write(dstWeight0.read(pix, 0) + w, pix, 0);
}


/**
 Compute shader to divide the weighted images.
 */
kernel void compositeDivide(
    uint2                            pix       [[ thread_position_in_grid ]],
    texture2d<float, access::read>  srcColour [[ texture(0) ]],
    texture2d<float, access::read>  srcWeight [[ texture(1) ]],
    texture2d<half,  access::write> dst       [[ texture(2) ]])
{
  dst.write(half4(srcColour.read(pix, 0) / srcWeight.read(pix, 0)), pix, 0);
}
