// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include "VarianceCutSampler.h"


namespace ar {

VarianceCutSampler::VarianceCutSampler(size_t depth)
    : depth_(depth)
{
}

std::vector<ar::LightSource> VarianceCutSampler::sample(const cv::Mat &image) {
  return {};
}

}
