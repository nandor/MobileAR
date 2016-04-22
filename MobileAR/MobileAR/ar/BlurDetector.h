// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#include <array>

#include <opencv2/opencv.hpp>



namespace ar {
  
/**
 Blur detector based on "Blur Detection for Digital Images Using Wavelet Transform"
 */
class BlurDetector {
 private:
  
  /**
   Haar Pyramid Level.
   */
  struct Level {
    // Low pass/Low pass.
    cv::Mat LL;
    // High pass/High pass.
    cv::Mat HH;
    // Low pass/High pass.
    cv::Mat LH;
    // High pass/Low pass.
    cv::Mat HL;
    // Edge map.
    cv::Mat EMap;
    // Local maxima window.
    cv::Mat EMax;
    // Window size.
    size_t n;
    
    Level(int rows, int cols, int n)
      : LL(rows, cols, CV_32F)
      , HH(rows, cols, CV_32F)
      , LH(rows, cols, CV_32F)
      , HL(rows, cols, CV_32F)
      , EMap(rows, cols, CV_32F)
      , EMax(rows / n, cols / n, CV_32F)
    {
    }
  };
  
 public:
  /**
   Creates a new detector.
   */
  BlurDetector(int rows, int cols, int threshold = 35);
  
  /** 
   Runs the detector on an image.
   */
  std::pair<float, float> operator() (const cv::Mat &gray);
  
 private:
  /**
   2D Haar Wavelet transform.
   */
  template<size_t N>
  void HaarTransform(
      const cv::Mat &LL0,
      cv::Mat &HH1,
      cv::Mat &LH1,
      cv::Mat &HL1,
      cv::Mat &LL1);
  
  /**
   Find the downscaled local maxima.
   */
  template<size_t N, size_t M>
  void LocalMaxima(const cv::Mat &EMap, cv::Mat &EMax);
  
  /**
   * Builds a level.
   */
  template<size_t N, size_t M>
  void BuildLevel(const cv::Mat &LL0, const std::shared_ptr<Level> &l);
  
 private:
  // Size of the cropped image.
  int rows_;
  int cols_;
  
  // Edge threshold.
  int threshold_;
  
  // All Haar levels.
  std::array<std::shared_ptr<Level>, 3> levels;
};
  
}
