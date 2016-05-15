// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#include <unordered_map>

#include <opencv2/aruco.hpp>
#include <opencv2/opencv.hpp>

#include <Eigen/Eigen>

#include "ar/Tracker.h"

namespace ar {

/**
 ArUco Marker Tracking.
 */
class ArUcoTracker : public Tracker {
 public:
  /**
   Creates an ArUco tracker.
   */
  ArUcoTracker(const cv::Mat k, const cv::Mat d);

  /**
   Detroys the ArUco tracker.
   */
  virtual ~ArUcoTracker();

 protected:
  /**
   Tracker-specific implementation of frame processing.
   */
  TrackingResult TrackFrameImpl(const cv::Mat &frame, float dt);

 private:
  /**
   solvePnP wrapper because OpenCV is funny.
   */
  std::pair<Eigen::Quaternion<float>, Eigen::Matrix<float, 3, 1>> solvePnP(
      const std::vector<Eigen::Matrix<float, 3, 1>> &world,
      const std::vector<cv::Point2f> &image,
      bool ransac);

 private:
  /// ArUco dictionary.
  cv::Ptr<cv::aruco::Dictionary> dict_;
  /// ArUco detector config.
  cv::Ptr<cv::aruco::DetectorParameters> params_;
  /// Objects points for a single marker.
  std::vector<Eigen::Matrix<float, 3, 1>> grid_;

  /// Marker being tracked.
  struct Marker {
    /// Position of the marker.
    Eigen::Matrix<float, 3, 1> t;
    /// Image points of the corners.
    std::vector<Eigen::Matrix<float, 3, 1>> world;
  };


  /// List of all markers.
  std::unordered_map<int, Marker> markers_;

  /// OpenCV to real world conversion.
  Eigen::Matrix<float, 4, 4> C;
};

}
