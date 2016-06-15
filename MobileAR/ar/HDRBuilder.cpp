// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include <cstdint>

#include <random>
#include <unordered_set>

#include <Eigen/Eigen>

#include "HDRBuilder.h"


namespace ar {

namespace {
  
/**
 * Weighting function.
 */
float w(uint8_t z) {
  return (z > 128.0f ? 256.0f - z : z) / 128.0f;
}

}

cv::Mat HDRBuilder::build(const std::vector<std::pair<cv::Mat, float>>& images) const {
  
  // Retrieve resolution. Drop alpha channels.
  assert(images.size() > 0);
  int rows = images[0].first.rows;
  int cols = images[0].first.cols;
  int chan = std::min(3, images[0].first.channels());
  
  // Split the input images into their R, G and B channels.
  std::vector<std::vector<std::pair<cv::Mat, float>>> split(chan);
  for (const auto &img : images) {

    // Make sure all images are of the same size.
    if (rows != img.first.rows || cols != img.first.cols || chan != img.first.channels()) {
      throw std::runtime_error("All exposures must be of the same size.");
    }
    
    // Split.
    std::vector<cv::Mat> channels;
    cv::split(img.first, channels);
    for (size_t i = 0; i < chan; ++i) {
      split[i].emplace_back(channels[i], img.second);
    }
  }
  
  // Recover all three channels separately.
  std::vector<cv::Mat> merged;
  for (const auto &channel : split) {
    merged.emplace_back(map(channel, recover(channel)));
  }
  
  // Merge the channels for the final image.
  cv::Mat hdr;
  cv::merge(merged, hdr);
  return hdr;
}
  
HDRBuilder::ResponseFunction HDRBuilder::recover(
    const std::vector<std::pair<cv::Mat, float>> &channel) const
{
  // Make sure people don't pass in silly stuff.
  assert(channel.size() > 0);
    
  // Sample a number of random points. The points should be uniformly distributed and
  // they should not have identical intensity values accross different images.
  std::vector<std::pair<uint32_t, uint32_t>> pts;
  {
    // Random number generator for uniform x and y coordinates.
    std::mt19937 generator(0);
    std::uniform_int_distribution<> dr(0, channel[0].first.rows - 1);
    std::uniform_int_distribution<> dc(0, channel[0].first.cols - 1);

    // Ensure no coordinate is sampled twice.
    std::unordered_set<uint64_t> hashCoord;

    // First, find a point for each graylevel.
    std::array<std::pair<int, int>, N + 1> points;
    for (auto &point : points) {
      point.first = point.second = -1;
    }
    for (const auto &img : channel) {
      const auto &mat = img.first;
      for (int r = 0; r < mat.rows; ++r) {
        for (int c = 0; c < mat.cols; ++c) {
          const auto &pix = mat.at<uint8_t>(r, c);
          points[pix] = { r, c };
        }
      }
    }
    for (int i = points.size() - 1; i >= 0; --i) {
      const int r = points[i].first;
      const int c = points[i].second;
      if (r < 0 || c < 0) {
        continue;
      }
      hashCoord.insert((static_cast<uint64_t>(r) << 32ull) | static_cast<uint64_t>(c));
      pts.emplace_back(points[i]);
    }
    
    // Sample points, ensuring they are distinct.
    while (pts.size() < M) {
      uint64_t coord = 0, r, c;
      do {
        r = dr(generator);
        c = dc(generator);

        // Ensure that no black pixels are used.
        bool okay = true;
        for (const auto &img : channel) {
          const auto &pix = img.first.at<uint8_t>(static_cast<int>(r), static_cast<int>(c));
          if (pix == 0) {
            okay = false;
            break;
          }
        }
        if (!okay) {
          continue;
        }
        coord = (r << 32ull) | c;
      } while (hashCoord.count(coord) > 0);

      hashCoord.insert(coord);
      pts.emplace_back(static_cast<uint32_t>(r), static_cast<uint32_t>(c));
    }
  }
  
  // The matrices encode the response function and smoothness.
  //
  // The response function is discretized into g(0), g(1), ..., g(n) and they are
  // weighted. A single row of the matrix encodes g(z) - ln(E_i) = ln dt. The rows
  // are weighted in order to reduce the importance of points at the two endpoints
  // which can be inaccurate due to noise.
  //
  // The gradient of the response curve is also fixed to 0, where the gradient is
  // defined as g''(z) = g(z - 1) - 2 * g(z) + g(z + 1). Values are weighted here
  // as well.
  Eigen::MatrixXf A = Eigen::MatrixXf::Zero(channel.size() * pts.size() + N, N + pts.size() + 1);
  Eigen::MatrixXf B = Eigen::MatrixXf::Zero(channel.size() * pts.size() + N, 1);
  
  // Fill in the matrix with constraints for pixel values.
  int k = 0;
  for (const auto &img : channel) {
    const auto &mat = img.first;
    const float dt = std::log(img.second);
    
    for (size_t i = 0; i < pts.size(); ++i, ++k) {
      const uint8_t &z = mat.at<uint8_t>(pts[i].first, pts[i].second);
      const float wz = w(z);
      
      A(k, z)         = +wz;
      A(k, N + i + 1) = -wz;
      B(k, 0)         = wz * dt;
    }
  }

  // Fix the middle of the curve to 0.
  A(k++, 127) = 1;
  
  // Add the smoothness constraint.
  for (int z = 1; z < N; ++k, ++z) {
    const float wz = w(z);
    A(k, z - 1) = +L * wz;
    A(k, z + 0) = -L * wz * 2;
    A(k, z + 1) = +L * wz;
    B(k, 0)     = 0;
  }
  
  // Ensure all rows were filled. If not, the matrix will be singular.
  assert(A.rows() == k && B.rows() == k);
  
  // Find the linear least mean squares solution using QR decomposition.
  const Eigen::MatrixXf x = A.fullPivHouseholderQr().solve(B);
  
  // Recover and return the response function.
  std::array<float, N + 1> t;
  for (size_t i = 1; i < N; ++i) {
    t[i] = x(i, 0);
  }
  t[0] = t[0 + 1];
  t[N] = t[N - 1];
  return { t };
}
  
cv::Mat HDRBuilder::map(
    const std::vector<std::pair<cv::Mat, float>> &channel,
    const ResponseFunction &g) const
{
  
  // Make sure people don't pass in silly stuff.
  assert(channel.size() > 0);
  int rows = channel[0].first.rows;
  int cols = channel[0].first.cols;
  
  // Compute the weighted average that depends on g and the w function.
  cv::Mat hdrS = cv::Mat::zeros(rows, cols, CV_32FC1);
  cv::Mat hdrW = cv::Mat::zeros(rows, cols, CV_32FC1);
  for (const auto &img : channel) {
    const float dt = std::log(img.second);
    
    for (int r = 0; r < rows; ++r) {
      const auto iptr = img.first.ptr<uint8_t>(r);
      auto sptr = hdrS.ptr<float>(r);
      auto wptr = hdrW.ptr<float>(r);
      
      for (int c = 0; c < cols; ++c) {
        const float wz = w(iptr[c]);

        sptr[c] += wz * (g(iptr[c]) - dt);
        wptr[c] += wz;
      }
    }
  }

  // Avoid division by zero.
  cv::Mat hdr = cv::Mat::zeros(rows, cols, CV_32FC1);
  for (int r = 0; r < rows; ++r) {
    const auto wptr = hdrW.ptr<float>(r);
    const auto sptr = hdrS.ptr<float>(r);
    auto hptr = hdr.ptr<float>(r);
    for (int c = 0 ; c < cols; ++c) {
      if (wptr[c] > 1e-5) {
        hptr[c] = std::exp(sptr[c] / wptr[c]);
      } else {
        hptr[c] = 1.0f;
      }
    }
  }
  
  return hdr;
}
  
}
