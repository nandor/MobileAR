// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#include "LightProbeSampler.h"

namespace ar {

/**
 * Class that implements median cut sampling.
 */
class VarianceCutSampler : public LightProbeSampler{
 public:
  VarianceCutSampler(size_t depth);

  std::vector<LightSource> sample(const cv::Mat &image);

 private:
  const size_t depth_;
};

}