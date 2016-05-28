// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#include <atomic>
#include <condition_variable>
#include <list>
#include <mutex>
#include <thread>
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

  /**
   Bundle Adjustment thread.
   */
  void RunBundleAdjustment();

  /**
   Performs bundle adjustment of multiple marker positions from different poses.
   
   @return Number of processed poses.
   */
  size_t BundleAdjust();

 private:
  /// Type for marker identifiers.
  typedef int MarkerID;

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

  /// Pose with marker measurements.
  struct Pose {
    /// Position of the camera.
    Eigen::Matrix<double, 3, 1> t;
    /// Orientation of the camera.
    Eigen::Quaternion<double> q;

    /// Observed markers.
    std::vector<std::pair<MarkerID, std::vector<cv::Point2f>>> observed;

    Pose() {
    }

    Pose(
        const Eigen::Matrix<double, 3, 1> &t,
        const Eigen::Quaternion<double> &q,
        const std::vector<int> &ids,
        const std::vector<std::vector<cv::Point2f>> &corners)
      : t(t)
      , q(q)
    {
      assert(ids.size() == corners.size());
      for (size_t i = 0; i < ids.size(); ++i) {
        observed.emplace_back(ids[i], corners[i]);
      }
    }
  };

  /// List of poses to be optimized for.
  std::list<Pose> poses_;
  /// Guard protecting poses.
  std::mutex poseMutex_;

  /// List of all markers.
  std::unordered_map<MarkerID, Marker> markers_;
  /// Guard protecting markers.
  std::mutex markerMutex_;

  /// Bundle adjustment thread.
  std::thread thread_;
  /// Flag to kill the thread.
  std::atomic<bool> running_;
  /// Condition variable to wake the thread up.
  std::condition_variable cond_;
};

}
