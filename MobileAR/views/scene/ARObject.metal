// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include <metal_graphics>
#include <metal_matrix>
#include <metal_stdlib>
#include <metal_texture>

using namespace metal;



/**
 Parameters passed to the shader.
 */
struct ARParams {
  /// Perspective projection matrix.
  float4x4 proj;
  /// View matrix.
  float4x4 view;
  /// Normal matrix.
  float4x4 norm;
};

/**
 Input to the vertex shader.
 */
struct ARObjectIn {
  packed_float3 vert;
  packed_float3 norm;
  packed_float2 uv;
};


/**
 Vertex shader to fragment shader.
 */
struct ARObjectInOut {
  float3 vert     [[ user(ver) ]];
  float3 norm     [[ user(norm) ]];
  float2 uv       [[ user(uv) ]];
  float4 position [[ position ]];
};


/**
 Output from the fragment shader.
 */
struct ARObjectOut {
  half2  normal     [[ color(0) ]];
  float4 material   [[ color(1) ]];
};



/**
 Vertex shader for the sphere
 */
vertex ARObjectInOut objectVert(
    constant ARObjectIn*     in     [[ buffer(0) ]],
    constant ARParams&       params [[ buffer(1) ]],
    uint                     id     [[ vertex_id ]])
{
  float3 vert = float3(in[id].vert);
  float3 norm = float3(in[id].norm);
  float2 uv = float2(in[id].uv);
  
  float4 wVert = params.view * float4(vert.x, vert.y, vert.z, 1.0);
  float4 wNorm = params.norm * float4(norm.x, norm.y, norm.z, 0.0);
  
  return { wVert.xyz, wNorm.xyz, uv, params.proj * wVert };
}


/**
 Fragment shader for the video background.
 */
fragment ARObjectOut objectFrag(
    ARObjectInOut   in  [[ stage_in ]])
{
  return {
    half2(normalize(in.norm).xy),
    { 1.0, 1.0, 1.0, 0.25 }
  };
}
