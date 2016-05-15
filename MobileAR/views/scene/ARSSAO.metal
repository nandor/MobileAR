// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include <metal_stdlib>

#include "ARParams.h"

using namespace metal;



/**
 Number of samples for ssao.
 */
constant uint SSAO_SAMPLES = 32;

/**
 Influence of the ambient occlusion factor.
 */
constant float SSAO_POWER = 5.0;

/**
 Radius of the SSAO sampling.
 */
constant float SSAO_FOCUS = 0.3;


/**
 Converts a depth value to a linear depth value.
 */
static float linearize(float d) {
  const float f = 100.0;
  const float n = 0.1;
  return (2 * n * f) / (f + n - d * (f - n));
}


/**
 Fragment shader to compute Screen Space Ambient Occlusion (SSAO).
 */
fragment half2 ssao(
    ARQuadInOut               in         [[ stage_in ]],
    constant ARCameraParams&  params     [[ buffer(0) ]],
    constant float3*          samples    [[ buffer(1) ]],
    constant float3*          random     [[ buffer(2) ]],
    texture2d<float>          texDepth   [[ texture(0) ]],
    texture2d<float>          texNormal  [[ texture(1) ]])
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
  const float3 v = vproj.xyz / vproj.w;

  // Compute the change-of-basis matrix.
  const float3 t = normalize(r - n * dot(r, n));
  const float3 b = cross(n, t);
  const float3x3 tbn = float3x3(t, b, n);

  // Sample points in a hemisphere around the origin.
  float ao = 0.0;
  for (uint i = 0; i < SSAO_SAMPLES; ++i) {
    // Project the sample in screen space.
    const float3 sample = tbn * samples[i];
    const float3 smplView = sample * SSAO_FOCUS + v;
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
