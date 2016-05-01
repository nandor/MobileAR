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
float w(int32_t z) {
  return (z > 127.0f ? 255.0f - z : z) / 127.0f;
}

}

cv::Mat HDRBuilder::build(const std::vector<std::pair<cv::Mat, float>>& images) const {
  
  // Retrieve resolution.
  assert(images.size() > 0);
  int rows = images[0].first.rows;
  int cols = images[0].first.cols;
  
  // Split the input images into their R, G and B channels.
  std::vector<std::pair<cv::Mat, float>> b, g, r;
  for (const auto &img : images) {
  
    // Make sure all images are of the same size.
    if (rows != img.first.rows || cols != img.first.cols) {
      throw std::runtime_error("All exposures must be of the same size.");
    }
    
    // Split.
    std::vector<cv::Mat> channels;
    cv::split(img.first, channels);
    if (channels.size() < 3) {
      throw std::runtime_error("BGR or BGRA images expected.");
    }
    b.emplace_back(channels[0], img.second);
    g.emplace_back(channels[1], img.second);
    r.emplace_back(channels[2], img.second);
  }
  
  // Recover all three channels separately.
  const auto cb = map(b, recover(b));
  const auto cg = map(g, recover(g));
  const auto cr = map(r, recover(r));
  
  // Merge the channels for the final image.
  cv::Mat hdr;
  cv::merge(std::vector<cv::Mat>{cb, cg, cr}, hdr);
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
    
    // Sample points, ensuring they are distinct.
    std::unordered_set<uint64_t> hashCoord;
    for (size_t i = 0; i < M; ++i) {
      
      uint64_t coord = 0, r, c;
      do {
        r = dr(generator);
        c = dc(generator);
        coord = (r << 32ull) | c;
      } while (hashCoord.count(coord) > 0);
      
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
  Eigen::MatrixXf A(channel.size() * pts.size() + N, N + pts.size() + 1);
  Eigen::MatrixXf B(channel.size() * pts.size() + N, 1);
  
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
  A(k++, 127) = 0;
  
  // Add the smoothness constraint.
  for (int z = 1; z <= N; ++z, ++k) {
    const float wz = w(z);
    
    A(k, z - 1) = wz;
    A(k, z + 0) = -2 * L * wz;
    A(k, z + 1) = wz;
    B(k, 0)     = 0;
  }
  
  // Ensure all rows were filled. If not, the matrix will be singular.
  assert(A.cols() == k && B.cols() == k);
  
  // Find the linear least mean squares solution using SVD.
  const Eigen::MatrixXf x = A.jacobiSvd(
      Eigen::ComputeThinU | Eigen::ComputeThinV
  ).solve(B);
  
  // Recover and return the response function.
  std::array<float, 256> t;
  for (size_t i = 0; i <= N; ++i) {
    t[i] = x(i, 0);
  }
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
  
  // Exponentiate the weighted averages.
  cv::Mat hdr;
  cv::exp(hdrS / hdrW, hdr);
  return hdr;
}
  
}
