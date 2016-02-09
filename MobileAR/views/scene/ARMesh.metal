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
 Input to the vertex shader.
 */
struct ARObjectIn {
  /// Vertex position.
  packed_float3 v;
  /// Normal vector.
  packed_float3 n;
  /// UV coordinate.
  packed_float2 uv;
  /// Tangent.
  packed_float3 t;
  /// Bitangent.
  packed_float3 b;
  /// 8 bytes padding.
  packed_float2 _;
};


/**
 Vertex shader to fragment shader.
 */
struct ARObjectInOut {
  float3 v        [[ user(vert) ]];
  
  float2 uv       [[ user(uv) ]];
  float4 position [[ position ]];
  
  float3 t        [[ user(t) ]];
  float3 b        [[ user(b) ]];
  float3 n        [[ user(n) ]];
};


/**
 Output from the fragment shader.
 */
struct ARObjectOut {
  half2  normal     [[ color(0) ]];
  float4 material   [[ color(1) ]];
  half2  ao         [[ color(2) ]];
};


/**
 Vertex shader for the object.
 */
vertex ARObjectInOut objectVert(
    constant ARObjectIn*     in     [[ buffer(0) ]],
    constant ARCameraParams& params [[ buffer(1) ]],
    constant ARObjectParams* object [[ buffer(2) ]],
    uint                     vid    [[ vertex_id ]],
    uint                     iid    [[ instance_id ]])
{
  // Input attribute.
  constant ARObjectIn& vert = in[vid];
  
  // Concatenate matrices.
  const float4x4 mv = params.view * object[iid].model;
  const float4x4 nv = params.normView * object[iid].normModel;
  
  // Compute view space vertex.
  float4 v = mv * float4(float3(vert.v), 1);
  
  // Transfer stuff to fragment shader.
  return {
      v.xyz,
      float2(in[vid].uv),
      params.proj * v,
      (nv * float4(float3(vert.t))).xyz,
      (nv * float4(float3(vert.b))).xyz,
      (nv * float4(float3(vert.n))).xyz
  };
}


/**
 Fragment shader for the virtual object.
 */
fragment ARObjectOut objectFrag(
    ARObjectInOut   in  [[ stage_in ]],
    texture2d<half> texDiff [[ texture(0) ]],
    texture2d<half> texSpec [[ texture(1) ]],
    texture2d<half> texNorm [[ texture(2) ]])
{
  // Decode the normal vector.
  constexpr sampler texSampler(address::clamp_to_edge, filter::linear);
  const float3 normal = float3(texNorm.sample(texSampler, in.uv).xyz) * 2 - 1;
  
  // Rebuild the change-of-basis matrix.
  const float3x3 tbn = float3x3(
      normalize(in.t),
      normalize(in.b),
      normalize(in.n)
  );
  
  // Encode the normal vector in 2 channels & sample diffuse & specular.
  return {
      half2(normalize(tbn * normal).xy),
      float4(
          float3(texDiff.sample(texSampler, in.uv).xyz),
          float(texSpec.sample(texSampler, in.uv).x)
      ),
      half2(0.0, 0.0)
  };
}


/**
 Vertex shader to fragment shader.
 */
struct ARPedestalInOut {
  float4 position [[ position ]];
  float3 normal   [[ user(normal) ]];
};


/**
 Vertex shader for the pedestal.
 */
vertex ARPedestalInOut pedestalVert(
    constant float4*         in     [[ buffer(0) ]],
    constant ARCameraParams& params [[ buffer(1) ]],
    constant ARObjectParams* object [[ buffer(2) ]],
    uint                     vid    [[ vertex_id ]],
    uint                     iid    [[ instance_id ]])
{
  return {
      params.proj * params.view * object[iid].model * in[vid],
      (params.normView * object[iid].normModel * float4(0, 1, 0, 0)).xyz
  };
}


/**
 Fragment shader for the pedestal.
 */
fragment float2 pedestalFrag(
    ARPedestalInOut   in  [[ stage_in ]])
{
  return normalize(in.normal).xy;
}
