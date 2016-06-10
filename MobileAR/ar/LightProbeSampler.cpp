// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include "LightProbeSampler.h"

namespace ar {


LightProbeSampler::LightProbeSampler(size_t depth, const cv::Mat &image)
  : depth_(depth)
  , count_(1 << depth_)
  , height_(image.rows)
  , image_(image.rows, image.cols, CV_32FC4)
  , illum_(image.rows, image.cols, CV_32FC1)
{
  cv::Mat floatImage;
  switch (image.type()) {
    case CV_32FC4: {
      floatImage = image;
      break;
    }
    case CV_32FC3: {
      cv::cvtColor(image, floatImage, CV_BGR2BGRA);
      break;
    }
    case CV_8UC3: {
      image.convertTo(floatImage, CV_32FC3);
      cv::cvtColor(floatImage, floatImage, CV_BGR2BGRA);
      break;
    }
    case CV_8UC4: {
      image.convertTo(floatImage, CV_32FC4);
      break;
    }
  }

  // Scale the pixels to compensate for over-representation.
  for (int r = 0; r < image_.rows; ++r) {
    const auto pi = floatImage.ptr<cv::Vec4f>(r);
    auto pj = image_.ptr<cv::Vec4f>(r);

    // Compensate by cos(phi).
    const float w = std::cos(r / height_ * M_PI - M_PI / 2.0f);

    for (int c = 0; c < image_.cols; ++c) {
      const auto &pix = pi[c];
      pj[c] = cv::Vec4f(pix[0] * w, pix[1] * w, pix[2] * w, pix[3]);
    }
  }

  // Compute the luminance map.
  for (int r = 0; r < image_.rows; ++r) {
    const auto pi = image_.ptr<cv::Vec4f>(r);
    auto pl = illum_.ptr<float>(r);

    for (int c = 0; c < image_.cols; ++c) {
      const auto &pix = pi[c];
      pl[c] = pix[2] * 0.0721 + pix[1] * 0.7154 + pix[0] * 0.2125;
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

  // Sum up light intensities. The value of each pixel is weighted inversely
  // to its distance from the cenroid.
  float sumB = 0.0f, sumG = 0.0f, sumR = 0.0f, sumW = 0.0f;
  for (int r = region.y0; r <= region.y1; ++r) {
    const auto &row = image_.ptr<cv::Vec4f>(r);
    for (int c = region.x0; c <= region.x1; ++c) {
      // Compute distance from centroid.
      const float d = std::sqrt((x - c) * (x - c) + (y - r) * (y - r));

      // Weight inversely proportional to distance.
      const float w = 1.0f / (d * d + 1.0f);

      // Sum up the weighted pixel.
      const auto &pix = row[c];
      sumB += w * pix[2];
      sumG += w * pix[1];
      sumR += w * pix[0];
      sumW += w;
    }
  }

  // Compute the area occupied by the light.
  const float area = (region.y1 - region.y0) * (region.x1 - region.x0) * (
      std::cos(M_PI / 2.0f - region.y0 / height_ * M_PI) +
      std::cos(M_PI / 2.0f - region.y1 / height_ * M_PI)
  ) / 2.0f;

  sumW *= (image_.cols * image_.cols / M_PI) / (area * 4);

  // Compute average intensity.
  const float b = sumB / (sumW * 255.0f);
  const float g = sumG / (sumW * 255.0f);
  const float r = sumR / (sumW * 255.0f);

  // Find the direction of the light source.
  const auto phi = static_cast<float>(M_PI / 2.0 - M_PI * y / image_.rows);
  const auto theta = static_cast<float>(2 * M_PI * x / image_.cols);

  const auto vx = static_cast<float>(cos(phi) * cos(theta));
  const auto vy = static_cast<float>(cos(phi) * sin(theta));
  const auto vz = static_cast<float>(sin(phi));

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
    x,
    area
  };
}

float LightProbeSampler::width(const Region &region) const {
  const float width = region.x1 - region.x0;
  return std::max(
      std::cos(region.y0 / height_ * M_PI - M_PI / 2.0f) * width,
      std::cos(region.y1 / height_ * M_PI - M_PI / 2.0f) * width
  );
}

float LightProbeSampler::height(const Region &region) const {
  return region.y1 - region.y0;
}

}
