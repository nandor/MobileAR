// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#include <vector>
#include <unordered_map>
#include <unordered_set>

#include <Eigen/Eigen>

#include <opencv2/opencv.hpp>


#include "ar/BlurDetector.h"



namespace ar {


/**
 Hash for graph nodes.
 */
struct PairHash {
  template<typename T, typename U>
  size_t operator() (const std::pair<T, U> &x) const {
    return std::hash<T>()(x.first) ^ std::hash<U>()(x.second);
  }
};


/**
 Exceptions reported by the environment stitcher.
 */
class EnvironmentBuilderException {
 public:
  enum Error {
    BLURRY,
    NOT_ENOUGH_FEATURES,
    NO_PAIRWISE_MATCHES,
    NO_GLOBAL_MATCHES
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
 HDR frame.
 */
struct HDRFrame {
  const cv::Mat bgr;
  const Eigen::Matrix<float, 3, 3> P;
  const Eigen::Matrix<float, 3, 3> R;
  const float time;

  HDRFrame(
      const cv::Mat &bgr,
      const Eigen::Matrix<float, 3, 3> &P,
      const Eigen::Matrix<float, 3, 3> &R,
      const float time)
    : bgr(bgr)
    , P(P)
    , R(R)
    , time(time)
  {
  }
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
    // Unique index.
    const int index;
    // Exposure level.
    const size_t level;
    // RGB version.
    const cv::Mat bgr;
    // List of keypoints.
    const std::vector<cv::KeyPoint> keypoints;
    // List of ORB descriptors.
    const cv::Mat descriptors;
    // Intrinsic matrix.
    Eigen::Matrix<float, 3, 3> P;
    // Extrinsic matrix (Camera pose).
    Eigen::Matrix<float, 3, 3> R;
    // Quaternion rotation.
    Eigen::Quaternion<double> q;
    // Flag to indicate if frame is optimized.
    bool optimized;

    Frame(
        int index,
        size_t level,
        const cv::Mat &bgr,
        const std::vector<cv::KeyPoint> &keypoints,
        const cv::Mat &descriptors,
        const Eigen::Matrix<float, 3, 3> &P,
        const Eigen::Matrix<float, 3, 3> &R,
        const Eigen::Quaternion<double> &q)
    : index(index)
    , level(level)
    , bgr(bgr)
    , keypoints(keypoints)
    , descriptors(descriptors)
    , P(P)
    , R(R)
    , q(q)
    , optimized(false)
    {
    }
  };

  /**
   Graph of feature matches.
   */
  typedef std::unordered_map<
      std::pair<int, int>,
      std::vector<std::pair<int, int>>,
      PairHash
  > MatchGraph;

  /**
   Graph of feature groups.
   */
  typedef std::vector<std::vector<std::pair<int, int>>> MatchGroup;

 public:

  /**
   Initializes the environment builder.
   */
  EnvironmentBuilder(
      size_t width,
      size_t height,
      const cv::Mat &k,
      const cv::Mat &d,
      bool undistort = false,
      bool checkBlur = false);

  /**
   Adds a new frame to the panorama.
   
   @throws EnvironmentBuilderException
   */
  void AddFrames(const std::vector<HDRFrame> &frames);

  /**
   Creates the panorama, performing bundle adjustment.
   */
  std::vector<std::pair<cv::Mat, float>> Composite();

 private:
  /**
   Returns the list of matches.
   
   @param reproj True if points are to be thresholded by gyro rotation.
   */
  MatchGraph Match(const Frame &query, const Frame &train);

  /**
   Optimizes the graph using Bundle Adjustment.
   */
  void Optimize();

  /**
   Groups the matches into buckets.
   */
  void GroupMatches();

  /**
   Projects all images.
   */
  std::vector<std::pair<cv::Mat, float>>  Project();

  /**
   Projects an image onto the panorama.
   */
  void Project(
     const cv::Mat &src,
     const Eigen::Matrix<float, 3, 3> &P,
     cv::Mat &dst,
     cv::Mat &w);

 private:
  // Width of the environment map.
  int width_;
  // Height of the environment map.
  int height_;

  // Next available index.
  int index_;

  /// Flag to enable distortion correction.
  bool undistort_;
  /// Flag to enable blur thresholding.
  bool checkBlur_;

  // Blur detector.
  std::unique_ptr<BlurDetector> blurDetector_;

  // List of processed frames.
  std::vector<Frame> frames_;
  std::unordered_map<int, Frame>* framesIdx_;

  // Distortion maps.
  cv::Mat mapX_;
  cv::Mat mapY_;

  // Keypoint detctor & matcher.
  cv::ORB orbDetector_;
  cv::BFMatcher bfMatcher_;

  // Graph of feature matches.
  MatchGraph graph_;
  MatchGroup groups_;

  // Enumeration of exposure levels.
  std::vector<float> exposures_;
};

}