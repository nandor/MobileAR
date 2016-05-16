// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#include <unordered_map>
#include <unordered_set>

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
  std::pair<Eigen::Quaternion<double>, Eigen::Matrix<double, 3, 1>> solvePnP(
      const std::vector<Eigen::Matrix<double, 3, 1>> &world,
      const std::vector<cv::Point2f> &image);

 private:
  /// ArUco dictionary.
  cv::Ptr<cv::aruco::Dictionary> dict_;
  /// ArUco detector config.
  cv::Ptr<cv::aruco::DetectorParameters> params_;

  /// Marker being tracked.
  struct Marker {
    /// Position of the marker.
    Eigen::Matrix<double, 3, 1> t;
    /// Rotation of the marker plane with respect to the horizontal plane.
    Eigen::Quaternion<double> q;

    /// Image points of the corners.
    std::vector<Eigen::Matrix<double, 3, 1>> world() const;
  };


  /// List of all markers.
  std::unordered_map<int, Marker> markers_;
};

}
