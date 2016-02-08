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
  MedianCutSampler(size_t depth);

  std::vector<LightSource> sample(const cv::Mat &image);

 private:
  const uint8_t depth_;
};

}