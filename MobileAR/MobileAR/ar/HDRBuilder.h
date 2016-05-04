// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#include <array>
#include <vector>

#include <opencv2/opencv.hpp>


namespace ar {

/**
 Recovers an HDR image from a set of images with known exposure.
 */
class HDRBuilder {
 public:
  
  cv::Mat build(const std::vector<std::pair<cv::Mat, float>>& images) const;
  
 private:
  /// Number of intensity levels.
  static constexpr size_t N = 0xFF;
  /// Number of points sampled.
  static constexpr size_t M = 256;
  /// Smoothness constraint.
  static constexpr float L = 50.0f;
  
  /**
   Discretized response function.
   */
  class ResponseFunction {
   public:
    /**
     * Creates a response function out of an array.
     */
    ResponseFunction(const std::array<float, 256> g)
      : g_(g)
    {
    }
    
    /**
     * Evaluates the response function for a value.
     */
    float operator() (const uint8_t &z) const {
      return g_[z];
    }
    
   private:
    std::array<float, 256> g_;
  };
  
  /**
   * Recovers the response function for a single channel.
   */
  ResponseFunction recover(
      const std::vector<std::pair<cv::Mat, float>> &channel) const;
  
  /**
   * Maps a response function over an image.
   */
  cv::Mat map(
      const std::vector<std::pair<cv::Mat, float>> &channel,
      const ResponseFunction &g) const;
  
};
  
}
