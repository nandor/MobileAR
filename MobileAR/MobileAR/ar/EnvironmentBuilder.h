// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#include <vector>

#include <Eigen/Eigen>

#include <opencv2/opencv.hpp>


#include "ar/BlurDetector.h"



namespace ar {

/**
 Exceptions reported by the environment stitcher.
 */
class EnvironmentBuilderException {
 public:
  enum Error {
    BLURRY,
    NOT_ENOUGH_FEATURES,
    NO_MATCHES
  };

  EnvironmentBuilderException(Error error)
    : error_(error)
  {
  }

  Error GetError() const {
    return error_;
  }

 private:
  const Error error_;
};

  
/**
 Encapsulates panoramic reconstruction logic.
 */
class EnvironmentBuilder {
 private:
  /**
   Information collected from a single frame.
   */
  struct Frame {
    // RGB version.
    const cv::Mat bgr;
    // List of keypoints.
    const std::vector<cv::KeyPoint> keypoints;
    // List of ORB descriptors.
    const cv::Mat descriptors;
    // Intrinsic matrix.
    const Eigen::Matrix<float, 3, 3> P;
    // Extrinsic matrix (Camera pose).
    const Eigen::Matrix<float, 3, 3> R;
    // Quaternion rotation.
    const Eigen::Quaternion<float> q;

    Frame(
        const cv::Mat &bgr,
        const std::vector<cv::KeyPoint> &keypoints,
        const cv::Mat &descriptors,
        const Eigen::Matrix<float, 3, 3> &P,
        const Eigen::Matrix<float, 3, 3> &R,
        const Eigen::Quaternion<float> &q)
    : bgr(bgr)
    , keypoints(keypoints)
    , descriptors(descriptors)
    , P(P)
    , R(R)
    , q(q)
    {
    }
  };
 public:

  /**
   Initializes the environment builder.
   */
  EnvironmentBuilder(
      size_t width,
      size_t height,
      const cv::Mat &k,
      const cv::Mat &d,
      bool undistort = false);

  /**
   Adds a new frame to the panorama.
   
   @throws EnvironmentBuilderException
   */
  void AddFrame(
      const cv::Mat &bgr,
      const Eigen::Matrix<float, 3, 3> &P,
      const Eigen::Matrix<float, 3, 3> &R);

 private:
  // Width of the environment map.
  size_t width_;
  // Height of the environment map.
  size_t height_;

  /// Flag to enable distortion correction.
  bool undistort_;

  // Blur detector.
  std::unique_ptr<BlurDetector> blurDetector_;

  // List of processed frames.
  std::vector<Frame> frames_;

  // Distortion maps.
  cv::Mat mapX_;
  cv::Mat mapY_;

  // Keypoint detctor & matcher.
  cv::Ptr<cv::ORB> detector_;
  std::unique_ptr<cv::BFMatcher> matcher_;
  
};

}