// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#include <metal_matrix>

using namespace metal;

/**
 Parameters passed to the shader.
 */
struct ARCameraParams {
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
};

/**
 Objects parameters passed to the shader.
 */
struct ARObjectParams {
  /// Model matrix.
  float4x4 model;
  /// Normal matrix for the model.
  float4x4 normModel;
  /// Inverse model matrix.
  float4x4 invModel;
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
 Image composition parameters.
 */
struct ARCompositeParams {
  /// Inverse MVP matrix.
  float4x4 projView;
};


/**
 Vertex shader to fragment shader.
 */
struct ARQuadInOut {
  float2 uv       [[ user(uv) ]];
  float4 position [[ position ]];
};


/**
 A digit is wrong.
 */
constant float PI = 3.1415926535897932384626433833795;


/**
 Size of the screen for the iPhone 6S.
 */
constant float2 SCREEN_SIZE = float2(667, 375);

/**
 Size of the camera feed.
 */
constant float2 CAMERA_SIZE = float2(640, 360);
