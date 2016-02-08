// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#include <metal_matrix>

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
 A digit is wrong.
 */
constant float PI = 3.1415926535897932384626433833795;