// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include "ar/Rotation.h"
#include "ar/Tracker.h"

namespace ar {

namespace {

/// Number of measurements to consider for the computation of the relative pose.
const size_t kRelativePoses = 50;
/// Gravitational acceleration, in cm/s^2.
static const float G = 9.80665 * 100;

}



Tracker::Tracker(const cv::Mat &k, const cv::Mat &d)
  : k(k)
  , d(d)
{
  K = Eigen::Matrix<double, 4, 4>::Identity();
  K(0, 0) = k.at<double>(0, 0);
  K(1, 1) = k.at<double>(1, 1);
  K(0, 2) = k.at<double>(0, 2);
  K(1, 2) = k.at<double>(1, 2);
}

Tracker::~Tracker() {
}


bool Tracker::TrackFrame(const cv::Mat &frame, float dt) {

  // Get the current rotation.
  const auto r = kfr.GetOrientation();

  // Delegate to the underlying tracker.
  const auto result = TrackFrameImpl(frame, dt);
  if (!result.tracked) {
    return false;
  }

  // Limit the size of the pose buffer.
  if (relativePoses.size() > kRelativePoses) {
    relativePoses.erase(relativePoses.begin(), relativePoses.begin() + 1);
  }

  // Find the average orientation between the marker frame and the world frame.
  if (relativePoses.size() > 0) {

    // Find the world rotation, as provided by the marker.
    Eigen::Quaternion<float> relativePose = QuaternionAverage(relativePoses);

    // Update the filter.
    kfr.UpdateMarker(result.q * relativePose, dt);
    kfp.UpdateMarker(result.t, dt);
  }

  relativePoses.push_back(result.q.inverse() * r);
  return true;
}

bool Tracker::TrackSensor(
    const Eigen::Quaternion<float> &q,
    const Eigen::Matrix<float, 3, 1> &a,
    const Eigen::Matrix<float, 3, 1> &w,
    float dt)
{
  const auto r = kfr.GetOrientation();

  kfr.UpdateIMU(q, w, dt);
  kfp.UpdateIMU(r.inverse().toRotationMatrix() * a * G, dt);
  
  return true;
}
  
}

