// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#include <vector>

#include <simd/simd.h>

#include <opencv2/opencv.hpp>

#include "Moments.h"


namespace ar {

/**
 Light source info.
 */
struct LightSource {
  /// Direction of the light source.
  const simd::float3 direction;
  /// Ambient intensity.
  const simd::float3 ambient;
  /// Diffuse intensity.
  const simd::float3 diffuse;
  /// Specular intensity.
  const simd::float3 specular;
  /// Region of the light source.
  const Region region;
  /// Y coordinate of centroid.
  const int centroidY;
  /// X coordinate of centroid.
  const int centroidX;
};

/**
 * Class that implements median cut sampling.
 */
class LightProbeSampler {
 public:
  /**
   Initializes the sampler with a luminance map.
   */
  LightProbeSampler(size_t depth, const cv::Mat &image);
  
  /**
   Cleanup.
   */
  virtual ~LightProbeSampler();

  /**
   Performs the sampling.
   */
  std::vector<LightSource> operator() ();
  
protected:
  /**
   * Splits the image vertically or horizontally into two and recurses.
   */
  virtual void split(const Region &region, int depth) = 0;
  
  /**
   Creates a light source out of a region.
   */
  LightSource sample(const Region &region, int y, int x) const;
    
 protected:
  /// Image to be sampled.
  const cv::Mat image_;
  /// Max depth for the algorithm.
  const size_t depth_;
  /// Number of light sources.
  const size_t count_;
  /// Luminance map.
  cv::Mat illum_;
  /// Output light sources.
  std::vector<LightSource> lights_;
};

}