// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include <metal_graphics>
#include <metal_matrix>
#include <metal_stdlib>
#include <metal_texture>

using namespace metal;

/**
 Number of light sources in a batch.
 */
constant uint LIGHTS_PER_BATCH = 32;

/**
 Factor in specular lighting.
 */
constant float MU = 0.3;

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
  /// Inverse projection matrix.
  float4x4 invProj;
  /// Inverse view matrix.
  float4x4 invView;
};

/**
 Structure defining a single directional light.
 */
struct ARDirectionalLight {
  /// Light direction.
  float3 dir;
  /// Diffuse colour.
  float3 ambient;
  /// Ambient colour.
  float3 diffuse;
  /// Specular colour.
  float3 specular;
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


/**
 Fragment shader to compute Screen Space Ambient Occlusion (SSAO).
 */
fragment float4 ssao(
    ARQuadInOut     in         [[ stage_in ]])
{
  return { 1, 1, 1, 1 };
}


/**
 Fragment shader to apply the effects of a batch of directional lights.
 */
fragment float4 lighting(
    ARQuadInOut                    in          [[ stage_in ]],
    constant ARParams&             params      [[ buffer(0) ]],
    constant ARDirectionalLight*   lights      [[ buffer(1) ]],
    texture2d<float, access::read> texDepth    [[ texture(0) ]],
    texture2d<float, access::read> texNormal   [[ texture(1) ]],
    texture2d<half, access::read>  texMaterial [[ texture(2) ]],
    texture2d<half, access::read>  texAO       [[ texture(3) ]])
{
  // Find the pixel coordinate based on UV.
  uint2 uv = uint2(
      texMaterial.get_width() * in.uv.x,
      texMaterial.get_height() * in.uv.y
  );
  
  // Read data from textures.
  const float2 normal = texNormal.read(uv).xy;
  const half4 material = texMaterial.read(uv);
  const float depth = texDepth.read(uv).x;
  
  // Decode normal vector, diffuse and specular and position.
  const float3 n = float3(normal.xy, sqrt(1 - dot(normal.xy, normal.xy)));
  const float3 albedo = float3(material.xyz);
  const float  spec = float(material.w) * 100.0 * MU;
  const float4 vproj = params.invProj * float4(
      in.uv.x * 2 - 1.0,
      1.0 - in.uv.y * 2,
      depth,
      1
  );
  const float3 v = vproj.xyz / vproj.w;
  
  // Find the eye direction.
  const float3 e = normalize(v);
  
  // Apply lighting equation for each light.
  float3 colour = float3(0.0, 0.0, 0.0);
  for (uint i = 0; i < LIGHTS_PER_BATCH; ++i) {
    // Fetch the light source data.
    constant ARDirectionalLight &light = lights[i];
    
    // Unpack light data.
    const float3 l = -normalize((params.norm * float4(light.dir, 0.0)).xyz);
    
    // Compute light contribution.
    const float diffFact = max(0.0, dot(n, l));
    const float specFact = max(0.0, dot(reflect(l, n), e));
    
    colour += (
        light.ambient +
        light.diffuse * diffFact +
        light.specular * pow(specFact, spec)
    );
  }
  
  return float4(colour * albedo, 1);
}
