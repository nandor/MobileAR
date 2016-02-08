// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include "MedianCutSampler.h"


namespace ar {

MedianCutSampler::MedianCutSampler(size_t depth)
  : depth_(depth)
  , count_(1 << depth)
  , lights_(depth)
{
}

std::vector<ar::LightSource> MedianCutSampler::sample(const cv::Mat &image) {

  // Save the image.
  image_ = image;

  // Ensure image is BGRA.
  if (image_.channels() != 4) {
    return {};
  }

  // Compute the luminance.
  std::vector<cv::Mat> channels;
  cv::split(image, channels);
  illum_ = cv::Mat(image.rows, image.cols, CV_32FC1);
  illum_ = channels[2] * 0.0721 + channels[1] * 0.7154 + channels[0] * 0.2125;

  // Compute the SST.
  sst_ = cv::Mat::zeros(illum_.rows + 1, illum_.cols + 1, CV_32FC1);
  for (int r = 0; r < illum_.rows; ++r) {
    const auto pl = illum_.ptr<float>(r);
    const auto ps0 = sst_.ptr<float>(r + 0);
    auto ps1 = sst_.ptr<float>(r + 1);

    for (int c = 0; c < illum_.cols; ++c) {
      ps1[c + 1] = ps1[c] + ps0[c + 1] - ps0[c] + pl[c];
    }
  }

  // Kicks of sampling.
  lights_.clear();
  split(1, 1, illum_.rows, illum_.cols, 0);
  return lights_;
}

void MedianCutSampler::split(int r0, int c0, int r1, int c1, int depth) {

  // If max depth was reached, return light source.
  if (depth >= depth_) {
    lights_.push_back(sample(r0, c0, r1, c1));
    return;
  }

  // Cut perpendicular to the longer side of the rectangle.
  const float total =
      sst_.at<float>(r1, c1) + sst_.at<float>(r0, c0) -
      sst_.at<float>(r0, c1) - sst_.at<float>(r1, c0);

  if (r1 - r0 >= c1 - c0) {
    auto bestRow = r0;
    auto bestDiff = std::numeric_limits<float>::max();

    for (int r = r0; r <= r1; ++r) {
      const float sum =
          sst_.at<float>( r, c1) + sst_.at<float>(r0, c0) -
          sst_.at<float>(r0, c1) - sst_.at<float>( r, c0);

      const float diff = std::abs(2.0f * sum - total);
      if (diff < bestDiff) {
        bestRow = r;
        bestDiff = diff;
      }
    }

    split(r0, c0, bestRow, c1, depth + 1);
    split(bestRow, c0, r1, c1, depth + 1);
  } else {
    auto bestCol = c0;
    auto bestDiff = std::numeric_limits<float>::max();

    for (int c = c0; c <= c1; ++c) {
      const float sum =
          sst_.at<float>(r1, c) + sst_.at<float>(r0, c0) -
          sst_.at<float>(r0,  c) - sst_.at<float>(r1, c0);

      const float diff = std::abs(2.0f * sum - total);
      if (diff < bestDiff) {
        bestCol = c;
        bestDiff = diff;
      }
    }

    split(r0, c0, r1, bestCol, depth + 1);
    split(r0, bestCol, r1, c1, depth + 1);
  }
}

ar::LightSource MedianCutSampler::sample(int r0, int c0, int r1, int c1) const {

  // Sum up light intensities.
  float sumB = 0.0f, sumG = 0.0f, sumR = 0.0f;
  for (int r = r0 - 1; r < r1; ++r) {
    const auto &row = image_.ptr<cv::Vec4b>(r);
    for (int c = c0 - 1; c < c1; ++c) {
      const auto &pix = row[c];

      sumB += pix[0];
      sumG += pix[1];
      sumR += pix[2];
    }
  }

  // Compute average intensity.
  const auto area = image_.rows * image_.cols;
  const float b = sumB / area / 255.0f;
  const float g = sumG / area / 255.0f;
  const float r = sumR / area / 255.0f;
  
  // Find the direction of the light source.
  const float y = (r1 + r0) / 2.0f;
  const float x = (c1 + c0) / 2.0f;

  const auto phi = static_cast<float>(2 * M_PI * x / image_.cols);
  const auto theta = static_cast<float>(M_PI * y / image_.rows);

  const auto vx = static_cast<float>(cos(phi) * sin(theta));
  const auto vy = static_cast<float>(cos(phi) * cos(theta));
  const auto vz = static_cast<float>(sin(theta));

  // Create the light source.
  return {
      simd::float3{
          -vx,
          -vy,
          -vz
      },
      simd::float3{
          r / 2.0f,
          g / 2.0f,
          b / 2.0f
      },
      simd::float3{
          r,
          g,
          b
      },
      simd::float3{
          r * 1.2f,
          g * 1.2f,
          b * 1.2f
      }
  };
}

}
