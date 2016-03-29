// Copyright (c) 2011 NVIDIA Corporation. All rights reserved.
//
// TO  THE MAXIMUM  EXTENT PERMITTED  BY APPLICABLE  LAW, THIS SOFTWARE  IS PROVIDED
// *AS IS*  AND NVIDIA AND  ITS SUPPLIERS DISCLAIM  ALL WARRANTIES,  EITHER  EXPRESS
// OR IMPLIED, INCLUDING, BUT NOT LIMITED  TO, NONINFRINGEMENT,IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.  IN NO EVENT SHALL  NVIDIA
// OR ITS SUPPLIERS BE  LIABLE  FOR  ANY  DIRECT, SPECIAL,  INCIDENTAL,  INDIRECT,  OR
// CONSEQUENTIAL DAMAGES WHATSOEVER (INCLUDING, WITHOUT LIMITATION,  DAMAGES FOR LOSS
// OF BUSINESS PROFITS, BUSINESS INTERRUPTION, LOSS OF BUSINESS INFORMATION, OR ANY
// OTHER PECUNIARY LOSS) ARISING OUT OF THE  USE OF OR INABILITY  TO USE THIS SOFTWARE,
// EVEN IF NVIDIA HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.

#include <metal_stdlib>
#include <metal_texture>

#include "ARParams.h"

using namespace metal;



/**
 Threshold for the difference between min and max luma.
 */
constant float FXAA_EDGE_THRESHOLD = 1.0f / 8.0f;

/**
 Minimum threshold to discard dark areas.
 */
constant float FXAA_EDGE_THRESHOLD_MIN = 1.0f / 16.0f;

/**
 Controls the removal of subpixel aliasing.
 */
constant float FXAA_SUBPIX_TRIM = 1.0f / 4.0f;

/**
 Preserves fine details.
 */
constant float FXAA_SUBPIX_CAP = 3.0f / 4.0f;

/**
 Number of search steps in a direction for FXAA.
 */
constant uint FXAA_SEARCH_STEPS = 16;

/**
 FXAA search stop threshold.
 */
constant float FXAA_SEARCH_THRESHOLD = 1.0f / 4.0f;

/**
 Scale for subpixel aliasing.
 */
constant float FXAA_SUBPIX_TRIM_SCALE = 1.0f / (1.0f - FXAA_SUBPIX_TRIM);


/**
 Converts an RGB value to a luma value, discarding the blue channel.
 */
static float luma(half3 rgb) {
  return rgb.y * (0.587f / 0.299f) + rgb.z;
}


/**
 Fragment shader to perform FXAA.
 */
fragment half4 fxaa(
    ARQuadInOut                     in     [[ stage_in ]],
    texture2d<half, access::sample> texRGB [[ texture(0) ]])
{
  constexpr sampler smpl(address::clamp_to_edge, filter::linear);
  
  // Sample RGB values.
  const half3 rgbNW = texRGB.sample(smpl, in.uv + float2(-1,-1) / SCREEN_SIZE).xyz;
  const half3 rgbW  = texRGB.sample(smpl, in.uv + float2(-1, 0) / SCREEN_SIZE).xyz;
  const half3 rgbSW = texRGB.sample(smpl, in.uv + float2(-1, 1) / SCREEN_SIZE).xyz;
  const half3 rgbN  = texRGB.sample(smpl, in.uv + float2( 0,-1) / SCREEN_SIZE).xyz;
  const half3 rgbM  = texRGB.sample(smpl, in.uv + float2( 0, 0) / SCREEN_SIZE).xyz;
  const half3 rgbS  = texRGB.sample(smpl, in.uv + float2( 0, 1) / SCREEN_SIZE).xyz;
  const half3 rgbNE = texRGB.sample(smpl, in.uv + float2( 1,-1) / SCREEN_SIZE).xyz;
  const half3 rgbE  = texRGB.sample(smpl, in.uv + float2( 1, 0) / SCREEN_SIZE).xyz;
  const half3 rgbSE = texRGB.sample(smpl, in.uv + float2( 1, 1) / SCREEN_SIZE).xyz;

  // Convert RGB to luminance.
  float lumaN  = luma(rgbN);
  const float lumaW  = luma(rgbW);
  const float lumaM  = luma(rgbM);
  const float lumaE  = luma(rgbE);
  float lumaS  = luma(rgbS);
  const float lumaNW = luma(rgbNW);
  const float lumaNE = luma(rgbNE);
  const float lumaSW = luma(rgbSW);
  const float lumaSE = luma(rgbSE);

  // Find the min & max luminance in the 3x3 neighbourhood.
  // If the diference between min and max exceeds an adaptive thredhold,
  // discard the pixel from being smoothed.
  const float rangeMin = min(lumaM, min(min(lumaN, lumaW), min(lumaS, lumaE)));
  const float rangeMax = max(lumaM, max(max(lumaN, lumaW), max(lumaS, lumaE)));
  const float range = rangeMax - rangeMin;
  if (range < max(FXAA_EDGE_THRESHOLD_MIN, rangeMax * FXAA_EDGE_THRESHOLD)) {
    return half4(rgbM, 1);
  }

  // Compute the amount of subpixel aliasing based on luminance difference.
  const float lumaL = (lumaN + lumaW + lumaE + lumaS) * 0.25;
  const float blendL = min(FXAA_SUBPIX_CAP, max(0.0,
      ((abs(lumaL - lumaM) / range) - FXAA_SUBPIX_TRIM) * FXAA_SUBPIX_TRIM_SCALE
  ));

  // 3x3 box filter to compute smoothed colour.
  const half3 rgbL = (
      rgbN  + rgbW  + rgbM  +
      rgbE  + rgbS  + rgbNW +
      rgbNE + rgbSW + rgbSE
  ) / 9;

  // Sobel filter to find horizontal and vertical edge strength.
  const float edgeVert =
      abs(0.25 * lumaNW - 0.5 * lumaN + 0.25 * lumaNE) +
      abs(0.50 * lumaW  - 1.0 * lumaM + 0.50 * lumaE ) +
      abs(0.25 * lumaSW - 0.5 * lumaS + 0.25 * lumaSE);
  const float edgeHorz =
      abs(0.25 * lumaNW - 0.5 * lumaW + 0.25 * lumaSW) +
      abs(0.50 * lumaN  - 1.0 * lumaM + 0.50 * lumaS ) +
      abs(0.25 * lumaNE - 0.5 * lumaE + 0.25 * lumaSE);

  
  // Choose gradients based on edge direction.
  const bool horzSpan = edgeHorz >= edgeVert;
  const float gradientN = abs((horzSpan ? lumaN : lumaW) - lumaM);
  const float gradientS = abs((horzSpan ? lumaS : lumaE) - lumaM);

  // Choose targe luminance values based on the higer gradient.
  float lumaG, gradientG, signG;
  if (gradientN < gradientS) {
    lumaG = ((horzSpan ? lumaS : lumaE) + lumaM) * 0.5;
    gradientG = gradientS * FXAA_SEARCH_THRESHOLD;
    signG = horzSpan ? +(1 / SCREEN_SIZE.y) : +(1 / SCREEN_SIZE.x);
  } else {
    lumaG = ((horzSpan ? lumaN : lumaW) + lumaM) * 0.5;
    gradientG = gradientN * FXAA_SEARCH_THRESHOLD;
    signG = horzSpan ? -(1 / SCREEN_SIZE.y) : -(1 / SCREEN_SIZE.x);
  }
  
  // Offset for search.
  const float2 offNP = (horzSpan ? float2(1.0, 0.0) : float2(0.0, 1.0)) / SCREEN_SIZE;
  
  // Choose start position based on direction.
  float2 posN, posP;
  posP.x = posN.x = in.uv.x + signG * (horzSpan ? 0.0 : 0.5);
  posP.y = posN.y = in.uv.y + signG * (horzSpan ? 0.5 : 0.0);
  
  // Search along the direction perpendicular to the gradient.
  bool doneN = false, doneP = false;
  float lumaEndN = lumaG, lumaEndP = lumaG;
  for (uint i = 0; !(doneN && doneP) && i < FXAA_SEARCH_STEPS; i++) {
    posN -= doneN ? 0 : offNP;
    posP += doneP ? 0 : offNP;
    if (!doneN) {
      lumaEndN = luma(texRGB.sample(smpl, posN).xyz);
      doneN = abs(lumaEndN - lumaG) >= gradientG;
    }
    if (!doneP) {
      lumaEndP = luma(texRGB.sample(smpl, posP).xyz);
      doneP = abs(lumaEndP - lumaG) >= gradientG;
    }
  }

  // Find the larger distance.
  const float dstN = horzSpan ? in.uv.x - posN.x : in.uv.y - posN.y;
  const float dstP = horzSpan ? posP.x - in.uv.x : posP.y - in.uv.y;

  // If there is not enough change in luminance, cancel out the subpixel offset.
  if (((lumaM - lumaG) < 0.0) == (((dstN < dstP ? lumaEndN : lumaEndP) - lumaG) < 0.0)) {
    signG = 0.0;
  }

  // Look up the pixel at a subpixel address in the direction of stronger gradient.
  const float subPixelOffset = (0.5 - (min(dstN, dstP) / (dstP + dstN))) * signG;
  const half3 rgbF = texRGB.sample(smpl, in.uv + (
      horzSpan ? float2(0, subPixelOffset) : float2(subPixelOffset, 0.0)
  )).xyz;

  // Mix based on computed subpixel aliasing.
  return half4(rgbL * blendL + (1.0 - blendL) * rgbF, 1);
}
