// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include <ceres/ceres.h>

#include "ar/EnvironmentBuilder.h"
#include "ar/Jet.h"
#include "ar/Rotation.h"


namespace ar {

namespace {

constexpr float kMinBlurThreshold = 0.01f;
constexpr size_t kMinFeatures = 50;
constexpr size_t kMinMatches = 25;
constexpr size_t kGapFrames = 5;
constexpr float kRansacReprojError = 5.0f;
constexpr float kLMedSReprojError = 3.0f;
constexpr float kMaxHammingDistance = 20.0f;
constexpr float kConfidenceInterval = 0.103f;
constexpr float kMinRotation = 15.0f * M_PI / 180.0f;
constexpr float kMaxRotation = 40.0f * M_PI / 180.0f;
constexpr float kMinPairs = 2;
constexpr float kMaxGroupStd = 15.0f;
constexpr float kHuberLossThreshold = 1.0f;
constexpr float operator"" _deg (long double deg) {
  return deg / 180.0f * M_PI;
}

}

/**
 Cost function to align rays.
 */
struct RayAlignCost {
  /// First observed point.
  Eigen::Matrix<double, 3, 1> x0;
  /// Second observed point.
  Eigen::Matrix<double, 3, 1> x1;
  /// First projection matrix.
  Eigen::Matrix<double, 3, 3> P0;
  /// Second projection matrix.
  Eigen::Matrix<double, 3, 3> P1;

  RayAlignCost(
     const Eigen::Matrix<double, 2, 1> &y0,
     const Eigen::Matrix<double, 2, 1> &y1,
     const Eigen::Matrix<double, 3, 3> &P0,
     const Eigen::Matrix<double, 3, 3> &P1)
    : P0(P0)
    , P1(P1)
  {
    // Unproject the two rays.
    x0 = Eigen::Matrix<double, 3, 1>(
        +(y0(0) - P0(0, 2)) / P0(0, 0),
        -(y0(1) - P0(1, 2)) / P0(1, 1),
        -1.0f
    ).normalized();
    x1 = Eigen::Matrix<double, 3, 1>(
        +(y1(0) - P1(0, 2)) / P1(0, 0),
        -(y1(1) - P1(1, 2)) / P1(1, 1),
        -1.0f
    ).normalized();
  }

  template<typename T>
  bool operator() (const T *const pq0, const T *const pq1, T *pr) const {

    // Map the parameters.
    Eigen::Map<const Eigen::Quaternion<T>> q0(pq0);
    Eigen::Map<const Eigen::Quaternion<T>> q1(pq1);
    Eigen::Map<Eigen::Matrix<T, 3, 1>> residual(pr);

    // Convert the rays to the correct datatype.
    Eigen::Matrix<T, 3, 1> r0 = x0.cast<T>();
    Eigen::Matrix<T, 3, 1> r1 = x1.cast<T>();

    // Compute weights that fall off as point departs from centre.
    const T &a0 = r0.dot(Eigen::Matrix<T, 3, 1>::UnitZ());
    const T &a1 = r1.dot(Eigen::Matrix<T, 3, 1>::UnitZ());

    // Convert them to world space.
    r0 = q0.inverse() * r0;
    r1 = q1.inverse() * r1;
    
    // Compute the residual.
    residual = (r0 - r1) * a0 * a1;
    return true;
  }
};


/**
 Cost function to optimize both points & poses.
 */
struct PointAlignCost {
  /// Observed point.
  const Eigen::Matrix<double, 2, 1> y;
  /// Projection matrix.
  const Eigen::Matrix<double, 3, 3> P;

  PointAlignCost(
     const Eigen::Matrix<double, 2, 1> &y,
     const Eigen::Matrix<double, 3, 3> &P)
    : y(y)
    , P(P)
  {
  }

  template<typename T>
  bool operator() (const T *const pq, const T *const px, T *pr) const {
    // Map the parameters.
    Eigen::Map<const Eigen::Quaternion<T>> q(pq);
    Eigen::Map<const Eigen::Matrix<T, 3, 1>> x(px);
    Eigen::Map<Eigen::Matrix<T, 2, 1>> residual(pr);

    // Compute the reprojection error.
    const Eigen::Matrix<T, 3, 1> w = q.toRotationMatrix() * x;
    const Eigen::Matrix<T, 3, 1> proj = P.cast<T>() * Eigen::Matrix<T, 3, 1>(+w(0), -w(1), -w(2));
    
    // Compute the residual.
    if (proj(2) > T(0.0)) {
      residual(0) = T(proj(0)) / proj(2) - y(0);
      residual(1) = T(proj(1)) / proj(2) - y(1);
    } else {
      residual(0) = T(0.0);
      residual(1) = T(0.0);
    }
    return true;
  }
};


/**
 Cost function to optimize for reprojection error.
 */
struct ReprojectionCost {
  /// First observed point.
  Eigen::Matrix<double, 2, 1> y0;
  /// Second observed point.
  Eigen::Matrix<double, 2, 1> y1;
  /// First projection matrix.
  Eigen::Matrix<double, 3, 3> P0;
  /// Second projection matrix.
  Eigen::Matrix<double, 3, 3> P1;

  ReprojectionCost(
     const Eigen::Matrix<double, 2, 1> &y0,
     const Eigen::Matrix<double, 2, 1> &y1,
     const Eigen::Matrix<double, 3, 3> &P0,
     const Eigen::Matrix<double, 3, 3> &P1)
    : y0(y0)
    , y1(y1)
    , P0(P0)
    , P1(P1)
  {
  }

  template<typename T>
  bool operator() (const T *const pq0, const T *const pq1, T *pr) const {

    // Map the parameters.
    Eigen::Map<const Eigen::Quaternion<T>> q0(pq0);
    Eigen::Map<const Eigen::Quaternion<T>> q1(pq1);
    Eigen::Map<Eigen::Matrix<T, 3, 1>> residual(pr);

    // Unproject a ray from the first point.
    const Eigen::Matrix<T, 3, 1> p0 = Eigen::Matrix<T, 3, 1>(
       +T((y0(0) - P0(0, 2)) / P0(0, 0)),
       -T((y0(1) - P0(1, 2)) / P0(1, 1)),
       -T(1)
    );

    // Project it onto the second image.
    const Eigen::Matrix<T, 3, 1> p1 =
        P1.cast<T>() *
        (q1 * q0.inverse()).toRotationMatrix() *
        p0;

    // Compute the reprojection error.
    residual(0) = p1(0) / p1(2) - y1(0);
    residual(1) = p1(1) / p1(2) - y1(1);
    return true;
  }
};

EnvironmentBuilder::EnvironmentBuilder(
    size_t width,
    size_t height,
    const cv::Mat &k,
    const cv::Mat &d,
    BAMethod baMethod,
    HMethod hMethod,
    bool undistort,
    bool checkBlur)
  : width_(static_cast<int>(width))
  , height_(static_cast<int>(height))
  , index_(0)
  , undistort_(undistort)
  , checkBlur_(checkBlur)
  , baMethod_(baMethod)
  , hMethod_(hMethod)
  , blurDetector_(checkBlur_ ? new BlurDetector(720, 1280) : nullptr)
  , orbDetector_(cv::ORB::create(1000))
  , bfMatcher_(cv::NORM_HAMMING, true)
{
  assert(k.rows == 3 && k.cols == 3);
  assert(d.rows == 4 && d.cols == 1);

  cv::initUndistortRectifyMap(k, d, {}, k, {1280, 720}, CV_16SC2, mapX_, mapY_);
}


void EnvironmentBuilder::AddFrames(const std::vector<HDRFrame> &rawFrames) {

  // Create the list of exposures.
  if (exposures_.empty()) {
    for (const auto &frame : rawFrames) {
      exposures_.push_back(frame.time);
    }
  } else {
    assert(exposures_.size() == rawFrames.size());
    for (size_t i = 0; i < rawFrames.size(); ++i) {
      assert(std::abs(rawFrames[i].time - exposures_[i]) < 1e-7);
    }
  }

  // Per-frame processing, creating a list of frames.
  std::vector<Frame> frames;
  {
    cv::Mat bgr, gray;
    for (size_t i = 0; i < rawFrames.size(); ++i) {
      const auto &frame = rawFrames[i];

      // Undistort the image if required & convert to grayscale.
      bgr = frame.bgr;
      if (undistort_) {
        cv::remap(bgr, bgr, mapX_, mapY_, cv::INTER_LINEAR);
      }
      cv::cvtColor(bgr, gray, CV_BGR2GRAY);

      // Check if the image is blurry.
      if (blurDetector_) {
        float per, blur;
        std::tie(per, blur) = (*blurDetector_)(gray);
        if (per < kMinBlurThreshold) {
          throw EnvironmentBuilderException(EnvironmentBuilderException::BLURRY);
        }
      }

      // Extract ORB features & descriptors and make sure we have enough of them.
      std::vector<cv::KeyPoint> keypoints;
      cv::Mat descriptors;
      orbDetector_->detectAndCompute(gray, {}, keypoints, descriptors);
      if (keypoints.size() < kMinFeatures) {
        throw EnvironmentBuilderException(EnvironmentBuilderException::NOT_ENOUGH_FEATURES);
      }

      // Downsize images in order to compress them.
      cv::Mat scaled;
      cv::resize(bgr, scaled, {640, 360});
      frames.emplace_back(
          index_ + i,
          i,
          scaled,
          keypoints,
          descriptors,
          frame.P,
          frame.R,
          Eigen::Quaternion<float>(frame.R).cast<double>()
      );
    }
  }

  // Pairwise matching between images of the same level, resulting in a local graph.
  std::vector<MatchGraph> matches;
  for (size_t i = 0; i < frames.size(); ++i) {
    for (size_t j = i + 1; j < frames.size(); ++j) {
      matches.push_back(Match(frames[i], frames[j]));
      if (matches.rbegin()->empty()) {
        throw EnvironmentBuilderException(EnvironmentBuilderException::NO_PAIRWISE_MATCHES);
      }
    }
  }

  // Global matching, between the two images and all other image.
  std::vector<MatchGraph> global;
  for (const auto &frame : frames) {
    // Save all the match graphs to other images.
    std::vector<MatchGraph> pairs;
    for (auto it = frames_.rbegin(); it != frames_.rend(); ++it) {
      const auto &match = Match(*it, frame);
      if (match.empty()) {
        continue;
      }
      global.emplace_back(match);
    }
  }

  // If not enough matches are avialble, bail out.
  if (frames_.size() != 0 && global.size() <= ((frames_.size() < 5) ? 0 : kMinPairs)) {
    throw EnvironmentBuilderException(EnvironmentBuilderException::NO_GLOBAL_MATCHES);
  }


  // Add the frame and matches to the buffer, merge graphs.
  std::copy(frames.begin(), frames.end(), std::back_inserter(frames_));
  std::copy(global.begin(), global.end(), std::back_inserter(matches));
  for (const auto &graph : matches) {
    for (const auto &node : graph) {
      std::copy(node.second.begin(), node.second.end(), std::back_inserter(graph_[node.first]));
    }
  }

  // Increment index only if frame accepted in order to keep it continouous.
  index_ += frames.size();
}

EnvironmentBuilder::MatchGraph EnvironmentBuilder::Match(
    const Frame &train,
    const Frame &query)
{
  // If the images is at the start or end of the sequence, relax conditions for gap closing.
  const bool gap =
      train.index < kGapFrames * exposures_.size() ||
      query.index < kGapFrames * exposures_.size();

  // Threshold by relative orientation. Orientation is extracted from the
  // quaternion in axis-angle format and must be less than 60 degrees.
  const float angle = std::abs(Angle(query.q.inverse() * train.q));
  if (gap ? (angle > kMaxRotation * 2.0f) : (angle > kMaxRotation)) {
    return {};
  }

  // Match the features from the current image to features from all other images. Matches
  // are also thresholded by their Hamming distance in order to keep the best matches.
  std::vector<cv::DMatch> matches;
  {
    bfMatcher_.match(query.descriptors, train.descriptors, matches);
    if (matches.size() < kMinMatches) {
      return {};
    }
    std::sort(matches.begin(), matches.end(), [] (const cv::DMatch &a, const cv::DMatch &b) {
      return a.distance < b.distance;
    });
    const auto maxHamming = std::min(kMaxHammingDistance, matches[0].distance * 5);
    matches.erase(std::remove_if(
        matches.begin(),
        matches.end(),
        [&matches, &maxHamming] (const cv::DMatch &m) {
          return m.distance < maxHamming;
        }
    ), matches.end());
    if (matches.size() < kMinMatches) {
      return {};
    }
  }

  // Threshold features by gyro reprojection error if the angle is small.
  // Large angles are not thresholded in order to avoid discarding correct loop closures.
  {
    // Jets with 3 elements, differentiating by noise.
    typedef Jet<float, 3> J;
    const J wx(0, 0);
    const J wy(0, 1);
    const J wz(0, 2);

    // Noise covariance.
    Eigen::Matrix<float, 3, 3> Q;
    if (gap) {
      Q <<
         6.00_deg,  0.00_deg,  0.00_deg,
         0.00_deg,  6.00_deg,  0.00_deg,
         0.00_deg,  0.00_deg, 20.00_deg;
    } else {
      Q <<
         6.00_deg,  0.00_deg,  0.00_deg,
         0.00_deg,  6.00_deg,  0.00_deg,
         0.00_deg,  0.00_deg, 15.00_deg;
      Q = Q * std::max(kMinRotation, angle);
    }

    // Relative rotation, including noise.
    const Eigen::Matrix<J, 3, 3> F =
      (query.P * query.R).cast<J>() *
      Eigen::Matrix<J, 3, 3>(
          Eigen::AngleAxis<J>(wx, Eigen::Matrix<J, 3, 1>::UnitX()) *
          Eigen::AngleAxis<J>(wy, Eigen::Matrix<J, 3, 1>::UnitY()) *
          Eigen::AngleAxis<J>(wz, Eigen::Matrix<J, 3, 1>::UnitZ())
      ) *
      (train.P * train.R).inverse().cast<J>();

    matches.erase(std::remove_if(
      matches.begin(),
      matches.end(),
      [&query, &train, &Q, &F](const cv::DMatch &m)
      {
        // Read the matching points.
        const auto &p0 = query.keypoints[m.queryIdx].pt;
        const auto &p1 = train.keypoints[m.trainIdx].pt;

        // Project the feature point from the current image onto the other image
        // using the rotation matrices obtained from gyroscope measurements.
        const auto proj = F * Eigen::Matrix<J, 3, 1>(
            J(p0.x),
            J(query.bgr.rows - p0.y - 1),
            J(1)
        );
        const auto px = proj.x() / proj.z();
        const auto py = J(train.bgr.rows) - proj.y() / proj.z() - J(1);
        if (proj.z() < J(0)) {
          return true;
        }

        // Extract the jacobian & compute the covariance.
        Eigen::Matrix<float, 2, 3> J;
        J <<
          px.e(0), px.e(1), px.e(2),
          py.e(0), py.e(1), py.e(2);
        Eigen::Matrix<float, 2, 2> S = J * Q * J.transpose();

        // Threshold by 95% confidence interval.
        Eigen::Matrix<float, 2, 1> mu(px.s, py.s);
        Eigen::Matrix<float, 2, 1> pp(p1.x, p1.y);
        return (pp - mu).transpose() * S.inverse() * (pp - mu) > kConfidenceInterval;
      }),
      matches.end()
    );
    if (matches.size() < kMinMatches) {
      return {};
    }
  }

  // Robustify features by finding a homography between the two planes.
  // RANSAC is used in order to ensure that the maximal number of features are
  // retained, while keeping the reprojection error small.
  std::vector<cv::DMatch> robustMatches;
  {
    std::vector<cv::Point2f> src, dst;
    cv::Mat mask;
    for (const auto &match : matches) {
      src.push_back(train.keypoints[match.trainIdx].pt);
      dst.push_back(query.keypoints[match.queryIdx].pt);
    }
    switch (hMethod_) {
      case HMethod::RANSAC: {
        cv::findHomography(src, dst, CV_RANSAC, kRansacReprojError, mask);
        if (matches.size() != mask.rows) {
          return {};
        }
        for (int i = 0; i < mask.rows; ++i) {
          if (mask.at<bool>(i, 0)) {
            robustMatches.push_back(matches[i]);
          }
        }

        // Probabilistic match test.
        if (robustMatches.size() < 5.9f + 0.22f * matches.size()) {
          return {};
        }
        break;
      }
      case HMethod::LMEDS: {
        cv::Mat h = cv::findHomography(src, dst, CV_RANSAC, kLMedSReprojError, mask);
        if (matches.size() != mask.rows) {
          return {};
        }
        for (int i = 0; i < mask.rows; ++i) {
          if (mask.at<bool>(i, 0)) {
            robustMatches.push_back(matches[i]);
          }
        }

        // Make sure at least 50\% of the points are inliers.
        if (robustMatches.size() < 0.5f * matches.size()) {
          return {};
        }
        break;
      }
    }
  }

  // Build the graph of matching features.
  MatchGraph graph;
  for (const auto &match : robustMatches) {
    graph[{query.index, match.queryIdx}].emplace_back(train.index, match.trainIdx);
    graph[{train.index, match.trainIdx}].emplace_back(query.index, match.queryIdx);
  }
  return graph;
}


std::vector<std::pair<cv::Mat, float>>  EnvironmentBuilder::Composite(
    const std::function<void(const std::string&)> &onProgress)
{
  // Start by grouping the matches and building the graph.
  GroupMatches();
  onProgress("Match Graph Optimization");

  // Global Bundle Adjustment.
  switch (baMethod_) {
    case BAMethod::RAYS:    OptimizeRays();    break;
    case BAMethod::POINTS:  OptimizePoints();  break;
    case BAMethod::VECTORS: OptimizeVectors(); break;
    case BAMethod::REPROJ:  OptimizeReproj();  break;
  }
  onProgress("Bundle Adjustment");

  // Final compositing.
  auto result = Project();
  onProgress("Compositing");

  return result;
}


void EnvironmentBuilder::OptimizeRays() {

  // Create the residual blocks based on pairwise matches.
  ceres::Problem problem;
  for (size_t i = 0; i < groups_.size(); ++i) {
    for (const auto &n0 : groups_[i]) {
      for (const auto &n1 : groups_[i]) {
        if (n0.first == n1.first) {
          continue;
        }
        frames_[n0.first].optimized = frames_[n1.first].optimized = true;

        problem.AddResidualBlock(
            new ceres::AutoDiffCostFunction<RayAlignCost, 3, 4, 4>(new RayAlignCost(
                n0.second.cast<double>(),
                n1.second.cast<double>(),
                frames_[n0.first].P.cast<double>(),
                frames_[n1.first].P.cast<double>()
            )),
            new ceres::HuberLoss(kHuberLossThreshold),
            frames_[n0.first].q.coeffs().data(),
            frames_[n1.first].q.coeffs().data()
        );
      }
    }
  }

  // Set up the quaternion parametrization.
  auto *qsParam = new QuaternionParametrization();
  for (auto &frame : frames_) {
    if (frame.optimized) {
      problem.SetParameterization(frame.q.coeffs().data(), qsParam);
    }
  }

  // Run the solver!
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
}

void EnvironmentBuilder::OptimizePoints() {

  // Estimate point locations.
  auto xs = EstimatePoints();

  // Create the residual blocks based on reprojection errors.
  ceres::Problem problem;
  for (size_t i = 0; i < groups_.size(); ++i) {
    for (const auto &node : groups_[i]) {
      // Mark the frame as optimized.
      frames_[node.first].optimized = true;

      // Creat the residual.
      problem.AddResidualBlock(
          new ceres::AutoDiffCostFunction<PointAlignCost, 2, 4, 3>(
              new PointAlignCost(node.second.cast<double>(), frames_[node.first].P.cast<double>())
          ),
          new ceres::HuberLoss(kHuberLossThreshold),
          frames_[node.first].q.coeffs().data(),
          xs[i].data()
      );
    }
  }

  // Set up the quaternion parametrization.
  auto *qsParam = new QuaternionParametrization();
  for (auto &frame : frames_) {
    if (frame.optimized) {
      problem.SetParameterization(frame.q.coeffs().data(), qsParam);
    }
  }
    
  // Run the solver!
  ceres::Solver::Summary summary;
  ceres::Solver::Options options;
  options.use_nonmonotonic_steps = true;
  options.use_inner_iterations = true;
  options.preconditioner_type = ceres::SCHUR_JACOBI;
  options.linear_solver_type = ceres::ITERATIVE_SCHUR;
  options.max_num_iterations = 100;
  options.gradient_tolerance = 1e-3;
  options.function_tolerance = 1e-3;
  options.minimizer_progress_to_stdout = true;
  ceres::Solve(options, &problem, &summary);
}


void EnvironmentBuilder::OptimizeVectors() {

  // Estimate point locations.
  auto xs = EstimatePoints();

  // Create the residual blocks based on reprojection errors.
  ceres::Problem problem;
  for (size_t i = 0; i < groups_.size(); ++i) {
    for (const auto &node : groups_[i]) {
      // Mark the frame as optimized.
      frames_[node.first].optimized = true;

      // Creat the residual.
      problem.AddResidualBlock(
          new ceres::AutoDiffCostFunction<PointAlignCost, 2, 4, 3>(
              new PointAlignCost(node.second.cast<double>(), frames_[node.first].P.cast<double>())
          ),
          new ceres::HuberLoss(kHuberLossThreshold),
          frames_[node.first].q.coeffs().data(),
          xs[i].data()
      );
    }
  }

  // Set up the quaternion parametrization.
  auto *qsParam = new QuaternionParametrization();
  for (auto &frame : frames_) {
    if (frame.optimized) {
      problem.SetParameterization(frame.q.coeffs().data(), qsParam);
    }
  }

  // Set up the unit vector parametrization.
  auto *xsParam = new UnitVectorParametrization();
  for (auto &x : xs) {
    problem.SetParameterization(x.data(), xsParam);
  }

  // Run the solver!
  ceres::Solver::Summary summary;
  ceres::Solver::Options options;
  options.use_nonmonotonic_steps = true;
  options.use_inner_iterations = true;
  options.preconditioner_type = ceres::SCHUR_JACOBI;
  options.linear_solver_type = ceres::ITERATIVE_SCHUR;
  options.max_num_iterations = 100;
  options.gradient_tolerance = 1e-3;
  options.function_tolerance = 1e-3;
  options.minimizer_progress_to_stdout = true;
  ceres::Solve(options, &problem, &summary);
}

void EnvironmentBuilder::OptimizeReproj() {

  // Create the residual blocks based on pairwise matches.
  ceres::Problem problem;
  for (size_t i = 0; i < groups_.size(); ++i) {
    for (const auto &n0 : groups_[i]) {
      for (const auto &n1 : groups_[i]) {
        if (n0.first == n1.first) {
          continue;
        }
        frames_[n0.first].optimized = frames_[n1.first].optimized = true;

        problem.AddResidualBlock(
            new ceres::AutoDiffCostFunction<RayAlignCost, 3, 4, 4>(new RayAlignCost(
                n0.second.cast<double>(),
                n1.second.cast<double>(),
                frames_[n0.first].P.cast<double>(),
                frames_[n1.first].P.cast<double>()
            )),
            new ceres::HuberLoss(kHuberLossThreshold),
            frames_[n0.first].q.coeffs().data(),
            frames_[n1.first].q.coeffs().data()
        );
      }
    }
  }

  // Set up the quaternion parametrization.
  auto *qsParam = new QuaternionParametrization();
  for (auto &frame : frames_) {
    if (frame.optimized) {
      problem.SetParameterization(frame.q.coeffs().data(), qsParam);
    }
  }
  
  // Run the solver!
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
}

std::vector<Eigen::Matrix<double, 3, 1>> EnvironmentBuilder::EstimatePoints() {

  // Create the vectors. Initialze each point to the average of points projected
  // through the 2D image points, normalized to unit length.
  std::vector<Eigen::Matrix<double, 3, 1>> xs(groups_.size(), Eigen::Vector3d(0, 0, 0));
  for (size_t i = 0; i < groups_.size(); ++i) {
    Eigen::Matrix<double, 3, 1> &x = xs[i];
    for (const auto &node : groups_[i]) {
      // Read the pose & point.
      const auto R = frames_[node.first].q.inverse().toRotationMatrix();
      const auto P = frames_[node.first].P.inverse();

      // Project to world space & normalize.
      const Eigen::Vector3f p = P * Eigen::Vector3f(node.second.x(), node.second.y(), 1.0f);
      x += R * Eigen::Vector3d(p(0), -p(1), -p(2)).normalized();
    }
    x.normalize();
  }

  return xs;
}

void EnvironmentBuilder::GroupMatches() {

  // Group the nodes by finding connected components using a depth first search.
  std::unordered_set<std::pair<int, int>, PairHash> visited;
  std::function<void(
      std::vector<std::pair<int, Eigen::Vector2f>> &group,
      const std::pair<int, int> &node)> dfs;
  dfs = [&] (std::vector<std::pair<int, Eigen::Vector2f>> &group, const std::pair<int, int> &node)
  {
    if (visited.find(node) != visited.end()) {
      return;
    }

    visited.insert(node);
    const auto &pt = frames_[node.first].keypoints[node.second].pt;
    group.push_back({node.first, Eigen::Vector2f(pt.x, pt.y) });
    for (const auto &next : graph_[node]) {
      dfs(group, next);
    }
  };

  for (const auto &node : graph_) {
    if (visited.find(node.first) != visited.end()) {
      continue;
    }
    groups_.emplace_back();
    dfs(*groups_.rbegin(), node.first);
  }
  
  // Remove groups where two features of the same image appear since that cannot happen.
  // Or it can due to noise, in which case the component must be thrown away.
  MatchGroup::iterator it = groups_.begin();
  while (it != groups_.end()) {

    // Check out if there are matches from the same image.
    std::unordered_map<int, std::vector<Eigen::Vector2f>> f;
    for (const auto &node : *it) {
      f[node.first].push_back(node.second);
    }

    // Clear the group, this is going to be robustified.
    it->clear();
    bool keep = true;

    // Traverse each group where feaures from the same image are merged together.
    for (const auto &group : f) {

      // Nothing to do with sole matches.
      if (group.second.size() == 1) {
        it->push_back({ group.first, group.second[0] });
        continue;
      }

      // Compute the mean & standard deviation in the group.
      float sumX = 0.0f, sumY = 0.0f, sumX2 = 0.0f, sumY2 = 0.0f;
      for (const auto &pt : group.second) {
        sumX += pt.x();
        sumY += pt.y();
        sumX2 += pt.x() * pt.x();
        sumY2 += pt.y() * pt.y();
      }

      const size_t n = group.second.size();
      const Eigen::Vector2f mean(sumX / n, sumY / n);
      const Eigen::Vector2f var(
          sumX2 / n - mean.x() * mean.x(),
          sumY2 / n - mean.y() * mean.y()
      );

      // Threshold by variance. If variance too large, discard group.
      if (var.norm() > kMaxGroupStd * kMaxGroupStd) {
        keep = false;
        break;
      }

      // Otherwise, replace point by the mean.
      it->push_back({ group.first, mean });
    }

    if (!keep) {
      it = groups_.erase(it);
    } else {
      ++it;
    }
  }
  std::cerr << groups_.size() << std::endl;
}


std::vector<std::pair<cv::Mat, float>>  EnvironmentBuilder::Project() {

  // Temp struct to store weighted averages.
  struct Level {
    cv::Mat weights;
    cv::Mat weighted;
  };
  std::vector<Level> levels(exposures_.size());
  for (size_t i = 0; i < exposures_.size(); ++i) {
    levels[i].weights = cv::Mat::zeros(height_, width_, CV_32FC1);
    levels[i].weighted = cv::Mat::zeros(height_, width_, CV_32FC3);
  }

  for (const auto &frame : frames_) {
    if (!frame.optimized) {
      continue;
    }

    // Adjust the projection matrix.
    Eigen::Matrix<float, 3, 3> proj = frame.P * 0.5f;
    proj(2, 2) = 1.0f;

    // Project each frame onto the screen.
    Project(
        frame.bgr,
        proj * frame.q.toRotationMatrix().cast<float>(),
        levels[frame.level].weighted,
        levels[frame.level].weights
    );
  }

  std::vector<std::pair<cv::Mat, float>> composited;
  for (size_t level = 0; level < exposures_.size(); ++level) {
    cv::Mat bgr = cv::Mat::zeros(height_, width_, CV_8UC3);
    for (int i = 0; i < height_; ++i) {
      for (int j = 0; j < width_; ++j) {
        if (levels[level].weights.at<float>(i, j) <= 1e-5) {
          bgr.at<cv::Vec3b>(i, j) = {0, 0, 0};
        } else {
          bgr.at<cv::Vec3b>(i, j) =
              levels[level].weighted.at<cv::Vec3f>(i, j) /
              levels[level].weights.at<float>(i, j);
        }
      }
    }
    composited.emplace_back(bgr, exposures_[level]);
  }
  return composited;
}


void EnvironmentBuilder::Project(
    const cv::Mat &src,
    const Eigen::Matrix<float, 3, 3> &P,
    cv::Mat &dstC,
    cv::Mat &dstW)
{
  assert(dstC.rows == dstW.rows);
  assert(dstC.cols == dstW.cols);

  // Adjust the projection matrix.
  for (int r = 0; r < dstC.rows; ++r) {
    for (int c = 0; c < dstC.cols; ++c) {
      // Projective texturing.
      const float phi = M_PI * (0.5f - static_cast<float>(r) / static_cast<float>(dstC.rows));
      const float theta = static_cast<float>(dstC.cols - c - 1) / static_cast<float>(dstC.cols) * M_PI * 2;
      const Eigen::Matrix<float, 3, 1> p = P * Eigen::Matrix<float, 3, 1>(
          std::cos(phi) * std::cos(theta),
          std::cos(phi) * std::sin(theta),
          std::sin(phi)
      );

      // Ensure the pixel is in bounds.
      const float u = src.cols - p.x() / p.z() - 1;
      const float v = p.y() / p.z();
      if (u < 0 || v < 0 || u >= src.cols || v >= src.rows || p.z() >= 0.0f) {
        continue;
      }

      // Find the weights of the pixel.
      const float w = std::min(
          std::min(u, src.cols - u - 1) / static_cast<float>(src.cols),
          std::min(v, src.rows - v - 1) / static_cast<float>(src.rows)
      ) + 5e-2;

      // Sample the texture.
      cv::Vec3b pix = src.at<cv::Vec3b>(int(v), int(u));

      // Add weights & weighted average.
      dstC.at<cv::Vec3f>(r, c) += w * pix;
      dstW.at<float>(r, c) += w;
    }
  }
}

}
