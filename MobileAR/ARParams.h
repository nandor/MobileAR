// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#include <simd/simd.h>


/**
 Parameters passed to metal shaders.
 */
typedef struct {
  /**
   Instrinsic camera parameters.
   */
  simd::float4x4 K;
  /**
   Pose (rotation + translation).
   */
  simd::float4x4 P;
  /**
   Radial & Tangential distortion.
   */
  simd::float4 dist;
} ARParams;

