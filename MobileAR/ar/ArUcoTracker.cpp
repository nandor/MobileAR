// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include <iomanip>

#include <fcntl.h>
#include <unistd.h>

#include <ceres/ceres.h>

#include "ar/ArUcoTracker.h"
#include "ar/Rotation.h"

namespace ar {

namespace {

/// Marker size.
constexpr float kMarkerSize =  4.6;
/// Minimum distance between graph poses.
constexpr float kMinDistance = 10.0f;
/// Minimum angle between two poses.
constexpr float kMinAngle = 60.0f / 180.0f * M_PI;
/// Objects points for a single marker.
const std::vector<Eigen::Matrix<double, 3, 1>> kGrid = {
  { -kMarkerSize / 2.0f, +kMarkerSize / 2.0f, 0.0f },
  { +kMarkerSize / 2.0f, +kMarkerSize / 2.0f, 0.0f },
  { +kMarkerSize / 2.0f, -kMarkerSize / 2.0f, 0.0f },
  { -kMarkerSize / 2.0f, -kMarkerSize / 2.0f, 0.0f }
};
/// OpenCV inversion matrix.
const Eigen::Matrix<double, 4, 4> kC = (Eigen::Matrix<double, 4, 4>() <<
     1,  0,  0,  0,
     0, -1,  0,  0,
     0,  0, -1,  0,
     0,  0,  0,  1
).finished();

template<typename T>
Eigen::Matrix<T, 4, 4> Compose(const Eigen::Quaternion<T> &q, const Eigen::Matrix<T, 3, 1> &t) {
  Eigen::Matrix<T, 4, 4> m = Eigen::Matrix<T, 4, 4>::Identity();
  m.block(0, 0, 3, 3) = q.toRotationMatrix();
  m.block(0, 3, 3, 1) = t;
  return m;
}

}

/**
 Guard to temporarily silence stderr.
 */
class Silence {
 public:
  Silence() {
    fflush(stderr);
    temp_ = dup(2);

    int null = open("/dev/null", O_WRONLY);
    dup2(null, 2);
    close(null);
  }

  ~Silence() {
    fflush(stderr);
    dup2(temp_, 2);
    close(temp_);
  }

 private:
  int temp_;
};

/**
 Residual block for both marker and pose.
 */
struct MarkerResidual {
 public:
  const Eigen::Matrix<double, 4, 4> p;
  const Eigen::Matrix<double, 4, 4> &k;
  const std::vector<cv::Point2f> &corners;

  MarkerResidual(
      const Eigen::Matrix<double, 4, 4> &k,
      const Eigen::Matrix<double, 3, 1> &t,
      const Eigen::Quaternion<double> &q,
      const std::vector<cv::Point2f> &corners)
    : p(Compose(q, t))
    , k(k)
    , corners(corners)
  {
    assert(corners.size() == 4);
  }

  template<typename T>
  bool operator() (
      const T *const pmt,
      const T *const pmq,
      T *pr) const
  {
    // Map inputs: pose rotation + translation.
    Eigen::Map<const Eigen::Matrix<T, 3, 1>> mt(pmt);
    Eigen::Map<const Eigen::Quaternion<T>> mq(pmq);

    // Compose the marker matrix.
    Eigen::Matrix<T, 4, 4> m = Eigen::Matrix<T, 4, 4>::Identity();
    m.block(0, 0, 3, 3) = mq.toRotationMatrix();
    m.block(0, 3, 3, 1) = mt;

    // Compute outputs: 8 residuals.
    for (size_t i = 0; i < kGrid.size(); ++i) {
      const Eigen::Matrix<T, 4, 1> gx(T(kGrid[i].x()), T(kGrid[i].y()), T(kGrid[i].z()), T(1));

      const Eigen::Matrix<T, 4, 1> x = k.cast<T>() * p.cast<T>() * m * gx;
      pr[i * 2 + 0] = x.x() / x.z() - T(corners[i].x);
      pr[i * 2 + 1] = x.y() / x.z() - T(corners[i].y);
    }

    return true;
  }
};


/**
 Residual block for marker + pose.
 */
struct MarkerPoseResidual {
 public:
  const Eigen::Matrix<double, 4, 4> k;
  const std::vector<cv::Point2f> &corners;

  MarkerPoseResidual(
      const Eigen::Matrix<double, 4, 4> &k,
      const std::vector<cv::Point2f> &corners)
    : k(k)
    , corners(corners)
  {
    assert(corners.size() == kGrid.size());
  }

  template<typename T>
  bool operator() (
      const T *const ppt,
      const T *const ppq,
      const T *const pmt,
      const T *const pmq,
      T *pr) const
  {
    // Map inputs: pose rotation + translation.
    Eigen::Map<const Eigen::Matrix<T, 3, 1>> pt(ppt);
    Eigen::Map<const Eigen::Quaternion<T>> pq(ppq);
    Eigen::Map<const Eigen::Matrix<T, 3, 1>> mt(pmt);
    Eigen::Map<const Eigen::Quaternion<T>> mq(pmq);

    // Compose the marker matrix.
    Eigen::Matrix<T, 4, 4> m = Eigen::Matrix<T, 4, 4>::Identity();
    m.block(0, 0, 3, 3) = mq.toRotationMatrix();
    m.block(0, 3, 3, 1) = mt;
    // Compose the pose matrix.
    Eigen::Matrix<T, 4, 4> p = Eigen::Matrix<T, 4, 4>::Identity();
    p.block(0, 0, 3, 3) = pq.toRotationMatrix();
    p.block(0, 3, 3, 1) = pt;

    // Compute outputs: 8 residuals.
    for (size_t i = 0; i < kGrid.size(); ++i) {
      const Eigen::Matrix<T, 4, 1> gx(T(kGrid[i].x()), T(kGrid[i].y()), T(kGrid[i].z()), T(1));

      const Eigen::Matrix<T, 4, 1> x = k.cast<T>() * p * m * gx;
      pr[i * 2 + 0] = x.x() / x.z() - T(corners[i].x);
      pr[i * 2 + 1] = x.y() / x.z() - T(corners[i].y);
    }

    return true;
  }
};


/**
 Residual for pose only.
 */
struct PoseResidual {
 public:
  const Eigen::Matrix<double, 4, 4> m;
  const Eigen::Matrix<double, 4, 4> &k;
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
    assert(corners.size() == 4);
  }

  template<typename T>
  bool operator() (
      const T *const ppt,
      const T *const ppq,
      T *pr) const
  {
    // Map inputs: pose rotation + translation.
    Eigen::Map<const Eigen::Matrix<T, 3, 1>> pt(ppt);
    Eigen::Map<const Eigen::Quaternion<T>> pq(ppq);

    // Compose the marker matrix.
    Eigen::Matrix<T, 4, 4> p = Eigen::Matrix<T, 4, 4>::Identity();
    p.block(0, 0, 3, 3) = pq.toRotationMatrix();
    p.block(0, 3, 3, 1) = pt;

    // Compute outputs: 8 residuals.
    for (size_t i = 0; i < kGrid.size(); ++i) {
      const Eigen::Matrix<T, 4, 1> gx(T(kGrid[i].x()), T(kGrid[i].y()), T(kGrid[i].z()), T(1));

      const Eigen::Matrix<T, 4, 1> x = k.cast<T>() * p * m.cast<T>() * gx;
      pr[i * 2 + 0] = x.x() / x.z() - T(corners[i].x);
      pr[i * 2 + 1] = x.y() / x.z() - T(corners[i].y);
    }
    
    return true;
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
  , running_(true)
  , thread_(&ArUcoTracker::RunBundleAdjustment, this)
{
}


ArUcoTracker::~ArUcoTracker() {
  running_ = false;
  thread_.join();
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
  ids.erase(std::remove_if(ids.begin(), ids.end(), [](int id) { return id % 5 != 0; }), ids.end());

  // If no markers were discovered yet, fix the coorinate system's origin to
  // the centre of the first marker that is detected.
  if (markers_.empty()) {
    std::lock_guard<std::mutex> lock(markerMutex_);
    markers_[ids[0]] = { { 0, 0, 0 }, { 1, 0, 0, 0 } };
    reference_ = ids[0];
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
          1.0f,
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
    r(0, 0) = rvec.at<double>(0, 0);
    r(1, 0) = rvec.at<double>(1, 0);
    r(2, 0) = rvec.at<double>(2, 0);
    q = Eigen::AngleAxis<double>{ r.norm(), r.normalized() },
    t = { tvec.at<double>(0, 0), tvec.at<double>(1, 0), tvec.at<double>(2, 0) };
  }

  // Iterate again and find the new markers. Express their position in the global
  // coordinate system of the markers. If new markers were added, perform bundle adjustment.
  // Concurrently, create an optimization problem to fix all the new poses concurrently.
  ceres::Problem problem;
  ceres::LocalParameterization *qsParam = new QuaternionParametrization();
  for (size_t i = 0; i < ids.size(); ++i) {
    std::unordered_map<int, Marker>::iterator marker = markers_.find(ids[i]);
    if (marker != markers_.end()) {
      continue;
    }

    // Locate the camera relative to the marker.
    auto r = solvePnP(kGrid, corners[i]);
    if (!std::get<2>(r)) {
      continue;
    }

    // Find the relative transformation.
    Eigen::Matrix4d P = Compose(q, t).inverse() * Compose(std::get<0>(r), std::get<1>(r));
    
    // Find the center point.
    Eigen::Vector4d centre = P * Eigen::Vector4d(0, 0, 0, 1);
    std::cout
        << "Discovered: " << std::endl
        << ids[i] << " "
        << centre.x() << " " << centre.y() << " " << centre.z() << " "
        << Eigen::Quaterniond(P.block<3, 3>(0, 0)).coeffs().transpose()
        << std::endl;

    // Create the marker in the hash map.
    {
      std::lock_guard<std::mutex> lock(markerMutex_);
      std::tie(marker, std::ignore) = markers_.insert(std::make_pair(ids[i], Marker{
          Eigen::Matrix<double, 3, 1>(centre.x(), centre.y(), centre.z()),
          Eigen::Quaternion<double>(P.block<3, 3>(0, 0))
      }));
    }

    // Add the marker to the list of markers.
    problem.AddResidualBlock(
        new ceres::AutoDiffCostFunction<MarkerResidual, 8, 3, 4>(new MarkerResidual(
            K,
            t,
            q,
            corners[i]
        )),
        nullptr,
        marker->second.t.data(),
        marker->second.q.coeffs().data()
    );
    problem.SetParameterization(marker->second.q.coeffs().data(), qsParam);
  }

  // Make sure that the quaternion is of unit length.
  if (problem.NumResidualBlocks() > 0) {
    std::lock_guard<std::mutex> lock(markerMutex_);

    ceres::Solver::Summary summary;
    ceres::Solver::Options options;
    options.use_nonmonotonic_steps = true;
    options.preconditioner_type = ceres::SCHUR_JACOBI;
    options.linear_solver_type = ceres::ITERATIVE_SCHUR;
    options.max_num_iterations = 20;
    options.gradient_tolerance = 1e-3;
    options.function_tolerance = 1e-3;
    options.minimizer_progress_to_stdout = false;
    {
      Silence output;
      ceres::Solve(options, &problem, &summary);
    }
  }

  // Check if the current pose is worth adding to the previous poses.
  {
    std::unique_lock<std::mutex> lock(poseMutex_);

    bool addPose = true;
    std::unordered_set<MarkerID> allMarkers;

    for (const auto &pose : poses_) {
      for (const auto &obs : pose.observed) {
        allMarkers.insert(obs.first);
      }

      // Ensure the poses are far enough from each other.
      if ((pose.t - t).norm() > kMinDistance) {
        continue;
      }
      if (std::abs(Angle(pose.q * q.inverse())) > kMinAngle) {
        continue;
      }

      // If not, skip adding the pose.
      addPose = false;
      break;
    }

    // Add the pose if it contains a marker not yet discovered.
    for (const auto &id : ids) {
      if (allMarkers.find(id) == allMarkers.end()) {
        addPose = true;
      }
    }

    if (addPose) {
      poses_.emplace_back(t, q, ids, corners);
      lock.unlock();
      cond_.notify_all();
    }
  }

  return {
      true,
      Eigen::Quaternion<float>(q.w(), q.x(), -q.y(), -q.z()),
      Eigen::Matrix<float, 3, 1>(t.x(), -t.y(), -t.z())
  };
}

std::tuple<Eigen::Quaternion<double>, Eigen::Matrix<double, 3, 1>, bool> ArUcoTracker::solvePnP(
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
  if (!cv::solvePnP(object, image, k, d, rvec, tvec, false, world.size() == 4 ? CV_P3P : CV_EPNP)) {
    return { Eigen::Quaterniond(), Eigen::Vector3d(), false };
  }

  // Convert to Eigen.
  Eigen::Matrix<double, 3, 1> r;
  r(0, 0) = rvec.at<double>(0, 0);
  r(1, 0) = rvec.at<double>(1, 0);
  r(2, 0) = rvec.at<double>(2, 0);

  // Convert rotation to angle-axis.
  return {
    Eigen::Quaternion<double>(Eigen::AngleAxis<double>{ r.norm(), r.normalized() }),
    Eigen::Matrix<double, 3, 1>{
      tvec.at<double>(0, 0),
      tvec.at<double>(1, 0),
      tvec.at<double>(2, 0)
    },
    true
  };
}

size_t ArUcoTracker::BundleAdjust() {

  // Create a copy of the markers.
  std::unordered_map<MarkerID, Marker> markers;
  {
    std::lock_guard<std::mutex> lock(markerMutex_);
    markers = markers_;
  }

  // Create the bundle adjustment problem for all the markers and poses.
  // The pose mutex protects only the vector - data stored in it is modified
  // only from this thread, so it is safe to unlock after creating the problem.
  std::list<std::pair<Eigen::Quaterniond, Eigen::Vector3d>> poses;
  std::set<double*> qsParams;
  ceres::Problem problem;
  {
    std::lock_guard<std::mutex> lock(poseMutex_);

    for (auto &pose : poses_) {
      poses.emplace_back(pose.q, pose.t);
      qsParams.insert(poses.back().first.coeffs().data());

      for (const auto &obs : pose.observed) {
        auto marker = markers.find(obs.first);
        problem.AddResidualBlock(
            new ceres::AutoDiffCostFunction<MarkerPoseResidual, 8, 3, 4, 3, 4>(
                new MarkerPoseResidual(K, obs.second)
            ),
            new ceres::HuberLoss(2.0f),
            poses.back().second.data(),
            poses.back().first.coeffs().data(),
            marker->second.t.data(),
            marker->second.q.coeffs().data()
        );
        qsParams.insert(marker->second.q.coeffs().data());
      }
    }
  }

  // Fix the first marker.
  {
    problem.SetParameterBlockConstant(markers[reference_].q.coeffs().data());
    problem.SetParameterBlockConstant(markers[reference_].t.data());
  }

  // Constrain quaternions to unit length.
  auto *qsParam = new QuaternionParametrization();
  for (const auto &q : qsParams) {
    problem.SetParameterization(q, qsParam);
  }

  // Solve the problem.
  ceres::Solver::Summary summary;
  ceres::Solver::Options options;
  options.use_inner_iterations = true;
  options.use_nonmonotonic_steps = true;
  options.preconditioner_type = ceres::SCHUR_JACOBI;
  options.linear_solver_type = ceres::ITERATIVE_SCHUR;
  options.max_num_iterations = 30;
  options.gradient_tolerance = 1e-3;
  options.function_tolerance = 1e-3;
  options.minimizer_progress_to_stdout = false;
  {
    Silence output;
    ceres::Solve(options, &problem, &summary);
  }

  // Copy back the optimized markers.
  {
    std::unique_lock<std::mutex> lock(markerMutex_);

    std::cout << "Optimized:" << std::endl;
    for (const auto &marker : markers) {
      markers_[marker.first].q = marker.second.q;
      markers_[marker.first].t = marker.second.t;

      std::cout
          << marker.first << " "
          << marker.second.t.transpose() << " "
          << marker.second.q.coeffs().transpose()
          << std::endl;
    }
  }

  // Copy the optimized poses.
  {
    std::unique_lock<std::mutex> lock(poseMutex_);
    auto pt = poses_.begin();
    for (const auto &pose : poses) {
      pt->q = pose.first;
      pt->t = pose.second;
      ++pt;
    }
  }

  return poses.size();
}

void ArUcoTracker::RunBundleAdjustment() {

  // Track the number of poses processed. Run BA once a new pose arrives.
  size_t processed = 0;

  while (running_) {
    {
      std::unique_lock<std::mutex> lock(poseMutex_);
      cond_.wait(lock, [&]() { return processed < poses_.size() || !running_; });
      if (!running_) {
        break;
      }
    }
    processed = BundleAdjust();
  }
}

}