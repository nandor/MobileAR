// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#include <Eigen/Eigen>

#include <opencv2/opencv.hpp>

#include "ar/KalmanFilter.h"


namespace ar {

/**
 Abstract base class for tracking systems.
 */
class Tracker {
 public:
  /**
   Creates a new tracker.
   */
  Tracker(const cv::Mat &k, const cv::Mat &d);

  /**
   Destroys the tracker.
   */
  virtual ~Tracker();

  /**
   Performs tracking based on camera data.
   */
  bool TrackFrame(const cv::Mat &frame, float dt);

  /**
   Performs tracking based on sensor data.
   */
  bool TrackSensor(
      const Eigen::Quaternion<float> &q,
      const Eigen::Matrix<float, 3, 1> &a,
      const Eigen::Matrix<float, 3, 1> &w,
      float dt);

  /**
   Returns the position of the camera.
   */
  Eigen::Matrix<float, 3, 1> GetPosition() const {
    return kfp.GetPosition();
  }

  /**
   Returns the orientation of the camera.
   */
  Eigen::Quaternion<float> GetOrientation() const {
    return kfr.GetOrientation();
  }

 protected:
  /**
   Data returned from the tracker.
   */
  struct TrackingResult {
    bool tracked;
    Eigen::Quaternion<float> q;
    Eigen::Matrix<float, 3, 1> t;
  };

  /**
   Tracker-specific implementation of frame processing.
   */
  virtual TrackingResult TrackFrameImpl(
      const cv::Mat &frame,
      float dt) = 0;

 protected:
  /// Intrinsic matrix.
  cv::Mat k;
  /// Calibrated distortion.
  cv::Mat d;

  // Kalman filter state.
  EKFOrientation<float> kfr;
  EKFPosition<float> kfp;

  // List of relative orientations, measured between the world and marker frame.
  std::vector<Eigen::Quaternion<float>> relativePoses;
};

}