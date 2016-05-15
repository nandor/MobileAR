// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include <ceres/ceres.h>

#include "ar/ArUcoTracker.h"

namespace ar {

namespace {

// Marker size.
constexpr float kMarkerSize =  4.6;

}

/**
 Residual block for both marker and pose.
 */
struct MarkerPoseResidual {
 public:

};


/**
 Marker only residual.
 */
struct MarkerResidual {

};



ArUcoTracker::ArUcoTracker(const cv::Mat k, const cv::Mat d)
  : Tracker(k, d)
  , dict_(cv::aruco::getPredefinedDictionary(cv::aruco::DICT_6X6_250))
  , params_(new cv::aruco::DetectorParameters())
  , C((Eigen::Matrix<float, 4, 1>() << 1, -1, -1, 1).finished().asDiagonal())
{
  grid_.emplace_back(-kMarkerSize / 2.0f, +kMarkerSize / 2.0f, 0.0f);
  grid_.emplace_back(+kMarkerSize / 2.0f, +kMarkerSize / 2.0f, 0.0f);
  grid_.emplace_back(+kMarkerSize / 2.0f, -kMarkerSize / 2.0f, 0.0f);
  grid_.emplace_back(-kMarkerSize / 2.0f, -kMarkerSize / 2.0f, 0.0f);
}

ArUcoTracker::~ArUcoTracker() {
}

Tracker::TrackingResult ArUcoTracker::TrackFrameImpl(
    const cv::Mat &frame,
    float dt)
{
  // Detect the markers & find their corners.
  std::vector<int> ids;
  std::vector<std::vector<cv::Point2f>> corners;
  cv::aruco::detectMarkers(frame, dict_, corners, ids, params_);
  if (ids.empty()) {
    return { false, {}, {} };
  }

  // If no markers were discovered yet, fix the coorinate system's origin to
  // the centre of the first marker that is detected.
  if (markers_.empty()) {
    markers_[ids[0]] = { Eigen::Matrix<float, 3, 1>(0.0f, 0.0f, 0.0f), grid_ };
  }

  // If none of the markers are connected to already seen ones, bail out.
  {
    bool found = false;
    for (const auto &id : ids) {
      if (markers_.find(id) != markers_.end()) {
        found = true;
        break;
      }
    }
    if (!found) {
      return { false, {}, {} };
    }
  }

  // Find the pose using RANSAC based on point correspondendes from known markers.
  Eigen::Quaternion<float> q;
  Eigen::Matrix<float, 3, 1> t;
  {
    std::vector<Eigen::Matrix<float, 3, 1>> world;
    std::vector<cv::Point2f> image;

    for (size_t i = 0; i < ids.size(); ++i) {
      // OpenCV never disappoints.
      assert(corners[i].size() == 4);

      // Fetch the marker from the database.
      auto marker = markers_.find(ids[i]);
      if (marker == markers_.end()) {
        continue;
      }

      // Fetch the world-image correspondences.
      assert(marker->second.world.size() == corners[i].size());
      for (size_t j = 0; j < corners[i].size(); ++j) {
        world.emplace_back(marker->second.world[j]);
        image.push_back(corners[i][j]);
      }
    }

    // Apply RANSAC with P3P to find the pose.
    std::tie(q, t) = solvePnP(world, image, true);
  }

  // Iterate again and find the new markers. Express their position in the global
  // coordinate system of the markers. If new markers were added, perform bundle adjustment.
  // Concurrently, create an optimization problem to fix all the new poses concurrently.
  ceres::Problem problem;
  for (size_t i = 0; i < ids.size(); ++i) {
    if (markers_.find(ids[i]) != markers_.end()) {
      continue;
    }

    // Locate the camera relative to the marker.
    auto r = solvePnP(grid_, corners[i], false);

    // Find the relative tranfromation.
    Eigen::Matrix<float, 4, 4> P =
      C.inverse() *
      (Eigen::Matrix<float, 4, 4>() << q.toRotationMatrix(), t, 0, 0, 0, 1).finished().inverse() *
      (Eigen::Matrix<float, 4, 4>() << r.first.toRotationMatrix(), r.second, 0, 0, 0, 1).finished() *
      C;

    std::vector<Eigen::Matrix<float, 3, 1>> grid;
    for (const auto &g : grid_) {
      Eigen::Vector4f x = P * Eigen::Vector4f(g.x(), g.y(), g.z(), 1.0f);
      grid.emplace_back(x.x(), x.y(), x.z());
    }

    // Find the center point.
    Eigen::Matrix<float, 4, 1> t = P * Eigen::Vector4f(0.0f, 0.0f, 0.0f, 1.0f);

    // Add the markers.
    markers_[ids[i]] = { Eigen::Matrix<float, 3, 1>(t.x(), t.y(), t.z()), grid };
  }


  ceres::Solver::Summary summary;
  ceres::Solver::Options options;
  options.use_nonmonotonic_steps = true;
  options.preconditioner_type = ceres::SCHUR_JACOBI;
  options.linear_solver_type = ceres::ITERATIVE_SCHUR;
  options.max_num_iterations = 30;
  options.gradient_tolerance = 1e-3;
  options.function_tolerance = 1e-3;
  options.minimizer_progress_to_stdout = true;
  ceres::Solve(options, &problem, &summary);

  return { true, q, t };
}

std::pair<Eigen::Quaternion<float>, Eigen::Matrix<float, 3, 1>> ArUcoTracker::solvePnP(
    const std::vector<Eigen::Matrix<float, 3, 1>> &world,
    const std::vector<cv::Point2f> &image,
    bool ransac)
{
  // Make sure we get sane data before we pass it to OpenCV to get an insane error message.
  assert(world.size() == image.size());

  // Convert points to OpenCV.
  std::vector<cv::Point3f> object;
  size_t n = world.size();
  for (const auto &w : world) {
    object.emplace_back(w.x(), w.y(), w.z());
  }

  // P3P is used because we have 4 coplanar points at our disposal.
  cv::Mat rvec, tvec;
  if (ransac && n > 4) {
    float confidence = 4.0f / static_cast<float>(n);
    cv::solvePnPRansac(object, image, k, d, rvec, tvec, false, 100, 5.0f, confidence, {}, CV_EPNP);
  } else {
    cv::solvePnP(object, image, k, d, rvec, tvec, false, n == 4 ? CV_P3P : CV_EPNP);
  }

  // Convert to eigen.
  Eigen::Matrix<float, 3, 1> r;
  r(0, 0) = +rvec.at<double>(0, 0);
  r(1, 0) = -rvec.at<double>(1, 0);
  r(2, 0) = -rvec.at<double>(2, 0);

  // Convert rotation to angle-axis.
  return {
    Eigen::Quaternion<float>(Eigen::AngleAxis<float>{ r.norm(), r.normalized() }),
    Eigen::Matrix<float, 3, 1>{
      +tvec.at<double>(0, 0),
      -tvec.at<double>(1, 0),
      -tvec.at<double>(2, 0)
    }
  };
}

}