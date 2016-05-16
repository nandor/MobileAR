// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include <ceres/ceres.h>

#include "ar/ArUcoTracker.h"

namespace ar {

namespace {

// Marker size.
constexpr float kMarkerSize =  4.6;
/// OpenCV to real world conversion.
const Eigen::Matrix<double, 4, 4> kC((Eigen::Vector4d() << 1, -1, -1, 1).finished().asDiagonal());
/// Objects points for a single marker.
const std::vector<Eigen::Matrix<double, 3, 1>> kGrid = {
  { -kMarkerSize / 2.0f, +kMarkerSize / 2.0f, 0.0f },
  { +kMarkerSize / 2.0f, +kMarkerSize / 2.0f, 0.0f },
  { +kMarkerSize / 2.0f, -kMarkerSize / 2.0f, 0.0f },
  { -kMarkerSize / 2.0f, -kMarkerSize / 2.0f, 0.0f }
};

template<typename T>
Eigen::Matrix<T, 4, 4> Compose(const Eigen::Quaternion<T> &q, const Eigen::Matrix<T, 3, 1> &t) {
  return (Eigen::Matrix<T, 4, 4>() << q.toRotationMatrix(), t, 0, 0, 0, 1).finished();
}

}

/**
 Residual block for both marker and pose.
 */
struct PoseResidual {
 public:
  const Eigen::Matrix<double, 4, 4> m;
  const Eigen::Matrix<double, 4, 4> k;
  const std::vector<cv::Point2f> &corners;

  PoseResidual(
      const Eigen::Matrix<double, 4, 4> &k,
      const Eigen::Matrix<double, 3, 1> &t,
      const Eigen::Quaternion<double> &q,
      const std::vector<cv::Point2f> &corners)
    : m(Compose(q, t))
    , k(k)
    , corners(corners)
  {
  }

  template<typename T>
  bool operator() (const T *const ppt, const T *const ppq, T *pr) const {

    // Map inputs: pose rotation + translation.
    Eigen::Map<const Eigen::Matrix<T, 3, 1>> pt(ppt);
    Eigen::Map<const Eigen::Quaternion<T>> pq(ppq);

    // Compose the pose matrix.
    Eigen::Matrix<T, 4, 4> p = Eigen::Matrix<T, 4, 4>::Identity();
    p.block(0, 0, 3, 3) = pq.toRotationMatrix();
    p.block(0, 3, 3, 1) = pt;

    // Map outputs: 8 residuals.
    for (size_t i = 0; i < kGrid.size(); ++i) {
      const Eigen::Matrix<T, 4, 1> gx(T(kGrid[i].x()), T(kGrid[i].y()), T(kGrid[i].z()), T(1));

      const Eigen::Matrix<T, 4, 1> x = (k * kC).cast<T>() * p * (kC * m).cast<T>() * gx;
      pr[i * 2 + 0] = x.x() / x.z() - T(corners[i].x);
      pr[i * 2 + 1] = x.y() / x.z() - T(corners[i].y);
    }

    return true;
  }
};


/**
 Marker only residual.
 */
struct MarkerResidual {
 public:
  template<typename T>
  bool operator() (
      const T *const pmt,
      const T *const pmq,
      const T *const ppt,
      const T *const ppq,
      T *pr) const
  {
    // Map inputs: marker + pose rotation/translation.
    Eigen::Map<const Eigen::Matrix<T, 3, 1>> mt(pmt);
    Eigen::Map<const Eigen::Quaternion<T>> mq(pmq);
    Eigen::Map<const Eigen::Matrix<T, 3, 1>> pt(ppt);
    Eigen::Map<const Eigen::Quaternion<T>> pq(ppq);

    // Map outputs: 8 residuals.
    Eigen::Map<Eigen::Matrix<T, 8, 1>> r(pr);



    return false;
  }
};



std::vector<Eigen::Matrix<double, 3, 1>> ArUcoTracker::Marker::world() const {
  std::vector<Eigen::Matrix<double, 3, 1>> world;
  for (const auto &g : kGrid) {
    world.push_back(q.toRotationMatrix() * g + t);
  }
  return world;
}


ArUcoTracker::ArUcoTracker(const cv::Mat k, const cv::Mat d)
  : Tracker(k, d)
  , dict_(cv::aruco::getPredefinedDictionary(cv::aruco::DICT_6X6_250))
  , params_(new cv::aruco::DetectorParameters())
{
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
    markers_[ids[0]] = { { 0, 0, 0 }, { 1, 0, 0, 0 } };
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
  Eigen::Quaternion<double> q;
  Eigen::Matrix<double, 3, 1> t;
  std::unordered_set<int> inliers;
  {
    std::vector<cv::Point3f> world;
    std::vector<cv::Point2f> image;
    std::vector<int> markerID;

    for (size_t i = 0; i < ids.size(); ++i) {
      // OpenCV never disappoints.
      assert(corners[i].size() == 4);

      // Fetch the marker from the database.
      auto marker = markers_.find(ids[i]);
      if (marker == markers_.end()) {
        continue;
      }

      // Fetch the markerse.
      const auto object = marker->second.world();

      // Array to recover inlier IDs from.
      markerID.push_back(ids[i]);

      // Fetch the world-image correspondences.
      assert(object.size() == corners[i].size());
      for (size_t j = 0; j < corners[i].size(); ++j) {
        world.emplace_back(object[j].x(), object[j].y(), object[j].z());
        image.push_back(corners[i][j]);
      }
    }

    // Apply RANSAC with EPNP to find the pose. If not enough markers are available,
    // the P3P algorithm is applied on 4 points for a single marker.
    std::vector<int> inlierCorners;
    cv::Mat rvec, tvec;
    bool success;
    if (world.size() == 4) {
      success = cv::solvePnP(
          world, image,
          k, d,
          rvec, tvec,
          false,
          CV_P3P
      );
      inliers = { markerID[0] };
    } else {
      success = cv::solvePnPRansac(
          world, image,
          k, d,
          rvec, tvec,
          false,
          100,
          5.0f,
          0.99f,
          inlierCorners,
          CV_EPNP
      );
      for (const auto &cornerID : inlierCorners) {
        inliers.insert(markerID[cornerID / 4]);
      }
    }
    if (!success) {
      return { false, {}, {} };
    }

    // Convert result to Eigen.
    Eigen::Matrix<double, 3, 1> r;
    r(0, 0) = +rvec.at<double>(0, 0);
    r(1, 0) = -rvec.at<double>(1, 0);
    r(2, 0) = -rvec.at<double>(2, 0);
    q = Eigen::AngleAxis<double>{ r.norm(), r.normalized() },
    t = { +tvec.at<double>(0, 0), -tvec.at<double>(1, 0), -tvec.at<double>(2, 0) };
  }

  // Iterate again and find the new markers. Express their position in the global
  // coordinate system of the markers. If new markers were added, perform bundle adjustment.
  // Concurrently, create an optimization problem to fix all the new poses concurrently.
  ceres::Problem problem;
  for (size_t i = 0; i < ids.size(); ++i) {
    const auto marker = markers_.find(ids[i]);
    if (marker != markers_.end()) {
      if (inliers.find(marker->first) != inliers.end()) {
        problem.AddResidualBlock(
            new ceres::AutoDiffCostFunction<PoseResidual, 8, 3, 4>(new PoseResidual(
                K,
                marker->second.t,
                marker->second.q,
                corners[i]
            )),
            new ceres::HuberLoss(1.0f),
            t.data(),
            q.coeffs().data()
        );
      }
    } else {
      // Locate the camera relative to the marker.
      auto r = solvePnP(kGrid, corners[i]);

      // Find the relative transformation.
      Eigen::Matrix4d P = (Compose(q, t) * kC).inverse() * Compose(r.first, r.second) * kC;
      
      // Find the center point.
      Eigen::Vector4d t = P * Eigen::Vector4d(0, 0, 0, 1);

      // Add the markers.
      markers_[ids[i]] = {
        Eigen::Matrix<double, 3, 1>(t.x(), t.y(), t.z()),
        Eigen::Quaternion<double>(P.block<3, 3>(0, 0))
      };
    }
  }


  ceres::Solver::Summary summary;
  ceres::Solver::Options options;
  options.use_nonmonotonic_steps = true;
  options.preconditioner_type = ceres::SCHUR_JACOBI;
  options.linear_solver_type = ceres::ITERATIVE_SCHUR;
  options.max_num_iterations = 30;
  options.gradient_tolerance = 1e-3;
  options.function_tolerance = 1e-3;
  options.minimizer_progress_to_stdout = false;


  std::cerr << "I " << t.transpose() << "  " << q.coeffs().transpose() << std::endl;
  ceres::Solve(options, &problem, &summary);
  std::cerr << "F " << t.transpose() << "  " << q.coeffs().transpose() << std::endl;

  return { true, q.cast<float>(), t.cast<float>() };
}


std::pair<Eigen::Quaternion<double>, Eigen::Matrix<double, 3, 1>> ArUcoTracker::solvePnP(
    const std::vector<Eigen::Matrix<double, 3, 1>> &world,
    const std::vector<cv::Point2f> &image)
{
  // Make sure we get sane data before we pass it to OpenCV to get an insane error message.
  assert(world.size() == image.size());

  // Convert points to OpenCV.
  std::vector<cv::Point3f> object;
  for (const auto &w : world) {
    object.emplace_back(w.x(), w.y(), w.z());
  }

  // P3P is used because we have 4 coplanar points at our disposal.
  cv::Mat rvec, tvec;
  cv::solvePnP(object, image, k, d, rvec, tvec, false, world.size() == 4 ? CV_P3P : CV_EPNP);

  // Convert to eigen.
  Eigen::Matrix<double, 3, 1> r;
  r(0, 0) = +rvec.at<double>(0, 0);
  r(1, 0) = -rvec.at<double>(1, 0);
  r(2, 0) = -rvec.at<double>(2, 0);

  // Convert rotation to angle-axis.
  return {
    Eigen::Quaternion<double>(Eigen::AngleAxis<double>{ r.norm(), r.normalized() }),
    Eigen::Matrix<double, 3, 1>{
      +tvec.at<double>(0, 0),
      -tvec.at<double>(1, 0),
      -tvec.at<double>(2, 0)
    }
  };
}

}