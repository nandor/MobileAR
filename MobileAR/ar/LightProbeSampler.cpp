// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include "LightProbeSampler.h"

namespace ar {


LightProbeSampler::LightProbeSampler(size_t depth, const cv::Mat &image)
  : image_(image)
  , depth_(depth)
  , count_(1 << depth_)
  , illum_(image.rows, image.cols, CV_8UC1)
{
  assert(image_.channels() == 4);

  // Compute the luminance map.
  for (int r = 0; r < image_.rows; ++r) {
    const auto pi = image_.ptr<cv::Vec4b>(r);
    auto pl = illum_.ptr<uint8_t>(r);

    for (int c = 0; c < image_.cols; ++c) {
      const auto &pix = pi[c];
      pl[c] = pix[0] * 0.0721 + pix[1] * 0.7154 + pix[2] * 0.2125;
    }
  }
}


LightProbeSampler::~LightProbeSampler() {
}


std::vector<LightSource> LightProbeSampler::operator() () {
  if (lights_.empty()) {
    split({ 1, 0, illum_.rows - 1, illum_.cols - 1 }, 0);
  }
  return lights_;
}


LightSource LightProbeSampler::sample(const Region &region, int y, int x) const {

  // Sum up light intensities.
  float sumB = 0.0f, sumG = 0.0f, sumR = 0.0f;
  for (int r = region.y0; r <= region.y1; ++r) {
    const auto &row = image_.ptr<cv::Vec4b>(r);
    for (int c = region.x0; c <= region.x1; ++c) {
      const auto &pix = row[c];

      sumB += pix[0];
      sumG += pix[1];
      sumR += pix[2];
    }
  }
  
  // Compute average intensity.
  const float area = region.area();
  const float scale = area * std::max(1ul, count_ / 4) * 255.0f;

  const float b = sumB / scale;
  const float g = sumG / scale;
  const float r = sumR / scale;

  // Find the direction of the light source.

  const auto phi = static_cast<float>(M_PI / 2.0 - M_PI * y / image_.rows);
  const auto theta = static_cast<float>(2 * M_PI * x / image_.cols);

  const auto vx = static_cast<float>(cos(phi) * sin(theta));
  const auto vy = static_cast<float>(sin(phi));
  const auto vz = static_cast<float>(cos(phi) * cos(theta));

  // Create the light source.
  return {
    simd::float3{
      -vx,
      -vy,
      -vz
    },
    simd::float3{
      r / 5.0f,
      g / 5.0f,
      b / 5.0f
    },
    simd::float3{
      r,
      g,
      b
    },
    simd::float3{
      r * 1.5f,
      g * 1.5f,
      b * 1.5f
    },
    region,
    y,
    x
  };
}

}
