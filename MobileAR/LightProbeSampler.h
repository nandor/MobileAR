// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#include <vector>

#include <simd/simd.h>

#include <opencv2/opencv.hpp>


namespace ar {

/**
 Light source info.
 */
struct LightSource {
  const simd::float3 direction;
  const simd::float3 ambient;
  const simd::float3 diffuse;
  const simd::float3 specular;

  LightSource(
      const simd::float3 &direction,
      const simd::float3 &ambient,
      const simd::float3 &diffuse,
      const simd::float3 &specular)
    : direction(direction)
    , ambient(ambient)
    , diffuse(diffuse)
    , specular(specular)
  {
  }
};

/**
 * Class that implements median cut sampling.
 */
class LightProbeSampler {
 public:
  virtual ~LightProbeSampler();

  virtual std::vector<LightSource> sample(const cv::Mat &image) = 0;
};

}