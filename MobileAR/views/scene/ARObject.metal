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
  /// Projection matrix.
  float4x4 proj;
  /// Inverse projection matrix.
  float4x4 invProj;
  /// View matrix.
  float4x4 view;
  /// Normal matrix for the view.
  float4x4 normView;
  /// Inverse view matrix.
  float4x4 invView;
  /// Model matrix.
  float4x4 model;
  /// Normal matrix for the model.
  float4x4 normModel;
  /// Inverse model matrix.
  float4x4 invModel;
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
 Pedestal vertex shader to fragment shader.
 */
struct ARPedestalInOut {
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
 Vertex shader for the object.
 */
vertex ARObjectInOut objectVert(
    constant ARObjectIn*     in     [[ buffer(0) ]],
    constant ARParams&       params [[ buffer(1) ]],
    uint                     id     [[ vertex_id ]])
{
  float3 vert = float3(in[id].vert);
  float3 norm = float3(in[id].norm);
  float2 uv = float2(in[id].uv);
  
  float4 wVert = params.view * float4(vert, 1.0);
  float4 wNorm = params.normView * float4(norm, 0.0);
  
  return { wVert.xyz, wNorm.xyz, uv, params.proj * wVert };
}


/**
 Fragment shader for the virtual object.
 */
fragment ARObjectOut objectFrag(
    ARObjectInOut   in  [[ stage_in ]])
{
  return {
    half2(normalize(in.norm).xy),
    { 1.0, 1.0, 1.0, 0.25 }
  };
}

/**
 Vertex shader for the pedestal.
 */
vertex ARPedestalInOut pedestalVert(
    constant float4*         in     [[ buffer(0) ]],
    constant ARParams&       params [[ buffer(1) ]],
    uint                     id     [[ vertex_id ]])
{
  return { params.proj * params.view * in[id] };
}


/**
 Fragment shader for the pedestal.
 */
fragment float2 pedestalFrag(
    constant ARParams& params [[ buffer(0) ]])
{
  return (normalize((params.normView * float4(0, 1, 0, 0)).xyz)).xy;
}
