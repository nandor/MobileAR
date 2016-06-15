// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include "ar/CalibTracker.h"

namespace ar {

namespace {

/// Size of the tracked pattern.
const cv::Size kPatternSize(4, 11);

}


CalibTracker::CalibTracker(const cv::Mat k, const cv::Mat d)
  : Tracker(k, d)
{
  // Create the grid of world positions of the circles.
  for (int i = 0; i < kPatternSize.height; i++ ) {
    for (int j = 0; j < kPatternSize.width; j++) {
      grid_.emplace_back((2 * j + i % 2) * 4.0f, i * 4.0f, 0.0f);
    }
  }

}

CalibTracker::~CalibTracker() {
}

Tracker::TrackingResult CalibTracker::TrackFrameImpl(const cv::Mat &frame, float dt) {

  // Detect the pattern.
  std::vector<cv::Point2f> corners;
  auto found = cv::findCirclesGrid(
      frame,
      kPatternSize,
      corners,
      cv::CALIB_CB_ASYMMETRIC_GRID | cv::CALIB_CB_CLUSTERING
  );
  if (!found) {
    return { false, {}, {} };
  }

  // If pattern found, use solvePnP to compute pose.
  cv::Mat rvec, tvec;
  cv::solvePnP({ grid_ }, corners, k, d, rvec, tvec, false, CV_EPNP);

  // Pass to Eigen.
  Eigen::Matrix<float, 3, 1> r;
  r(0, 0) =  rvec.at<double>(0, 0);
  r(1, 0) = -rvec.at<double>(1, 0);
  r(2, 0) = -rvec.at<double>(2, 0);

  // Convert rotation to angle-axis.
  return {
      true,
      Eigen::Quaternion<float>(Eigen::AngleAxis<float>{ r.norm(), r.normalized() }),
      Eigen::Matrix<float, 3, 1>{
          +tvec.at<double>(0, 0),
          -tvec.at<double>(1, 0),
          -tvec.at<double>(2, 0)
      }
  };
}

std::vector<std::vector<cv::Point2f>> CalibTracker::GetMarkers() const {
  return {};
}

}
