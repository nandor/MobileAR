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
 Number of light sources in a batch.
 */
constant uint LIGHTS_PER_BATCH = 32;

/**
 Factor in specular lighting.
 */
constant float MU = 0.3;

/**
 Number of samples for ssao.
 */
constant uint SSAO_SAMPLES = 32;

/**
 Influence of the ambient occlusion factor.
 */
constant float SSAO_POWER = 8.0;

/**
 Radius of the SSAO sampling.
 */
constant float SSAO_FOCUS = 0.30;

/**
 Size of the screen for the iPhone 6S.
 */
constant float2 SCREEN_SIZE = float2(667, 375);

/**
 Very small number.
 */
constant float EPS = 1e-2;


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
 Converts a depth value to a linear depth value.
 */
static float linearize(float d) {
  const float f = 100.0;
  const float n = 0.1;
  return (2 * n * f) / (f + n - d * (f - n));
}



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


/**
 Fragment shader to compute Screen Space Ambient Occlusion (SSAO).
 */
fragment half2 ssao(
    ARQuadInOut         in         [[ stage_in ]],
    constant ARParams&  params     [[ buffer(0) ]],
    constant float3*    samples    [[ buffer(1) ]],
    constant float3*    random     [[ buffer(2) ]],
    texture2d<float>    texDepth   [[ texture(0) ]],
    texture2d<float>    texNormal  [[ texture(1) ]])
{
  // Find the pixel coordinate based on UV.
  const uint2 uv = uint2(SCREEN_SIZE * in.uv);
  
  // Read data from textures.
  const float2 normal = texNormal.read(uv).xy;
  const float depth = texDepth.read(uv).x;
  const float3 r = random[((uv.x & 3) << 2) | (uv.y & 3)];
  
  // Decode the normal vector and world space position.
  const float3 n = float3(normal.xy, sqrt(1 - dot(normal.xy, normal.xy)));
  const float4 vproj = params.invProj * float4(
      2.0 * in.uv.x - 1.0,
      1.0 - in.uv.y * 2,
      depth,
      1
  );
  
  // The vertex position is moved a tiny bit into the direction of the normal
  // in order to avoid self-occlusion on larger planar surfaces.
  const float3 v = vproj.xyz / vproj.w + n * EPS;
  
  // Compute the change-of-basis matrix.
  const float3 t = normalize(r - n * dot(r, n));
  const float3 b = cross(n, t);
  const float3x3 tbn = float3x3(t, b, n);
  
  // Sample points in a hemisphere around the origin.
  float ao = 0.0;
  for (uint i = 0; i < SSAO_SAMPLES; ++i) {
    // Project the sample in screen space.
    const float3 smplView = tbn * samples[i] * SSAO_FOCUS + v;
    const float4 smplProj = params.proj * float4(smplView, 1);
    const float3 smpl = smplProj.xyz / smplProj.w;
    
    // Sample the depth.
    const uint2 smplUV = uint2(
        texDepth.get_width() * (smpl.x + 1.0) * 0.5,
        texDepth.get_height() * (1.0 - smpl.y) * 0.5
    );
    const float smplDepth = texDepth.read(smplUV).x;
    
    // Accumulate occlusion.
    const float range = smoothstep(
        0.0,
        1.0,
        SSAO_FOCUS / abs(linearize(depth) - linearize(smplDepth))
    );
    ao += step(smplDepth, smpl.z) * range;
  }
  
  return {
      half(min(1.0, pow(1 - ao / SSAO_SAMPLES, SSAO_POWER))),
      0.0f
  };
}


/**
 4x4 blur for the ssao shader.
 */
fragment half2 ssaoBlur(
    ARQuadInOut     in       [[ stage_in ]],
    texture2d<half> texAOEnv [[ texture(0) ]])
{
  // Find the pixel coordinate based on UV.
  const int2 uv = int2(SCREEN_SIZE * in.uv);
  
  // Blur in a 4x4 neighbourhood.
  float ao = 0.0f;
  for (int j = -2; j < 2; ++j) {
    for (int i = -2; i < 2; ++i) {
      ao += texAOEnv.read(uint2(uv + int2(j, i))).x;
    }
  }
  return {
    half(ao / 16.0f),
    texAOEnv.read(uint2(uv)).y
  };
}

                         
/**
 Fragment shader to apply the effects of a batch of directional lights.
 */
fragment float4 lighting(
    ARQuadInOut                   in          [[ stage_in ]],
    constant ARParams&            params      [[ buffer(0) ]],
    constant ARDirectionalLight*  lights      [[ buffer(1) ]],
    texture2d<float>              texDepth    [[ texture(0) ]],
    texture2d<float>              texNormal   [[ texture(1) ]],
    texture2d<half>               texMaterial [[ texture(2) ]],
    texture2d<half>               texAOEnv    [[ texture(3) ]],
    texture2d<half>               envMap      [[ texture(4) ]])
{
  constexpr sampler envSampler(address::repeat, filter::linear);
  
  // Find the pixel coordinate based on UV.
  const uint2 uv = uint2(SCREEN_SIZE * in.uv);
  
  // Read data from textures.
  const float2 normal = texNormal.read(uv).xy;
  const half4 material = texMaterial.read(uv);
  const float depth = texDepth.read(uv).x;
  const half2 aoEnv = texAOEnv.read(uv).xy;
  
  // Decode ao, normal vector, diffuse and specular and position.
  const float ao = aoEnv.x;
  const float env = aoEnv.y;
  const float3 n = float3(normal.xy, sqrt(1 - dot(normal.xy, normal.xy)));
  const float3 objAlbedo = float3(material.xyz);
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
  
  // Sample the environment map.
  const float3 ed = normalize(reflect(e, n));
  const float eu = atan2(ed.x, ed.z) / (2 * PI);
  const float ev = acos(ed.y) / PI;
  const float3 envAlbedo = float4(envMap.sample(envSampler, {eu, ev})).xyz;
  
  // Abedo is a mix between object color the sampled environment map.
  const float3 albedo = mix(objAlbedo, envAlbedo, env);
  
  // Apply lighting equation for each light.
  float3 ambient = float3(0.0, 0.0, 0.0);
  float3 diffuse = float3(0.0, 0.0, 0.0);
  float3 specular = float3(0.0, 0.0, 0.0);
  for (uint i = 0; i < LIGHTS_PER_BATCH; ++i) {
    // Fetch the light source data.
    constant ARDirectionalLight &light = lights[i];
    
    // Compute light contribution.
    const float diffFact = max(0.0, dot(n, light.dir));
    const float specFact = max(0.0, dot(reflect(light.dir, n), e));
    
    ambient += light.ambient;
    diffuse += light.diffuse * diffFact;
    specular += light.specular * pow(specFact, spec);
  }
  
  // Sample the environment map.
  return float4(albedo * (ao * ambient + diffuse + specular), 1);
}

