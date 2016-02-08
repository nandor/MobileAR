// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#include "LightProbeSampler.h"

namespace ar {

/**
 * Class that implements median cut sampling.
 */
class MedianCutSampler : public LightProbeSampler{
 public:
  /**
   * Initializes the median cut sampler.
   */
  MedianCutSampler(size_t depth);

  /**
   * Samples an image, returning 2^depth_ lights.
   */
  std::vector<LightSource> sample(const cv::Mat &image);

 private:
  /**
   * Splits the image vertically or horizontally into two and recurses.
   */
  void split(int r0, int c0, int r1, int c1, int depth);

  /**
   * Creates a light source from a region.
   */
  LightSource sample(int r0, int c0, int r1, int c1) const;

 private:
  /// Max depth for the algorithm.
  const size_t depth_;
  /// Input image.
  cv::Mat image_;
  /// Luminance map.
  cv::Mat illum_;
  /// Sum of Squares Table.
  cv::Mat sst_;
  /// Output light sources.
  std::vector<LightSource> lights_;
};

}