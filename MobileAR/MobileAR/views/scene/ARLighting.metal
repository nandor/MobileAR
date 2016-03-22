// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include <metal_stdlib>

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
 Fragment shader to apply the effects of a batch of directional lights.
 */
fragment float4 lighting(
    ARQuadInOut                   in          [[ stage_in   ]],
    constant ARCameraParams&      params      [[ buffer(0)  ]],
    constant ARDirectionalLight*  lights      [[ buffer(1)  ]],
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
  const float  spec = float(material.w + 0.01) * 100.0 * MU;
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