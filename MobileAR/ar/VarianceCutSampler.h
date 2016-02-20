// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#include "LightProbeSampler.h"
#include "Moments.h"

namespace ar {

/**
 * Class that implements median cut sampling.
 */
class VarianceCutSampler : public LightProbeSampler{
 public:
  /**
   Initializes the variance cut sampler.
   */
  VarianceCutSampler(size_t depth, const cv::Mat &image);
  
 private:
  /**
   * Splits the image vertically or horizontally into two and recurses.
   */
  void split(const Region &region, int depth);
  
  /**
   Computes variance in a region.
   */
  int64_t variance(const Region &region);
  
 private:
  /// Moments.
  Moments<0, 0> m00_;
  Moments<0, 1> m01_;
  Moments<1, 0> m10_;
  Moments<0, 2> m02_;
  Moments<2, 0> m20_;
};

}