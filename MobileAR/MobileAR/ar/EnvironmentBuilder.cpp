// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include <ceres/ceres.h>

#include "ar/EnvironmentBuilder.h"
#include "ar/Rotation.h"


namespace ar {

namespace {

constexpr float kMinBlurThreshold = 0.01f;
constexpr size_t kMinFeatures = 50;
constexpr size_t kMinMatches = 25;
constexpr size_t kMinGroupSize = 3;
constexpr float kRansacReprojError = 5.0f;
constexpr float kMaxHammingDistance = 20.0f;
constexpr float kMaxReprojThreshold = 150.0f;
constexpr float kMaxRotation = 60.0f * M_PI / 180.0f;
constexpr float kMinPairs = 3;

}

struct RayAlignCost {
  /// First observed point.
  Eigen::Matrix<double, 2, 1> y0;
  /// Second observed point.
  Eigen::Matrix<double, 2, 1> y1;
  /// First projection matrix.
  Eigen::Matrix<double, 3, 3> P0;
  /// Second projection matrix.
  Eigen::Matrix<double, 3, 3> P1;

  RayAlignCost(
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

    // Unproject the two rays.
    Eigen::Matrix<T, 3, 1> r0 = Eigen::Matrix<T, 3, 1>(
        +T((y0(0) - P0(0, 2)) / P0(0, 0)),
        -T((y0(1) - P0(1, 2)) / P0(1, 1)),
        -T(1.0f)
    ).normalized();
    Eigen::Matrix<T, 3, 1> r1 = Eigen::Matrix<T, 3, 1>(
        +T((y1(0) - P1(0, 2)) / P1(0, 0)),
        -T((y1(1) - P1(1, 2)) / P1(1, 1)),
        -T(1.0f)
    ).normalized();

    // Convert them to world space.
    r0 = q0.inverse() * r0;
    r1 = q1.inverse() * r1;
    
    // Compute the residual.
    residual = r0 - r1;
    return true;
  }
};

EnvironmentBuilder::EnvironmentBuilder(
    size_t width,
    size_t height,
    const cv::Mat &k,
    const cv::Mat &d,
    bool undistort,
    bool checkBlur)
  : width_(static_cast<int>(width))
  , height_(static_cast<int>(height))
  , index_(0)
  , undistort_(undistort)
  , checkBlur_(checkBlur)
  , blurDetector_(checkBlur_ ? new BlurDetector(720, 1280) : nullptr)
  , orbDetector_(1000)
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
      orbDetector_(gray, {}, keypoints, descriptors);
      if (keypoints.size() < kMinFeatures) {
        throw EnvironmentBuilderException(EnvironmentBuilderException::NOT_ENOUGH_FEATURES);
      }

      // Get the rotation quaternion.
      frames.emplace_back(
          index_ + i,
          i,
          bgr,
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

  // Threshold by relative orientation. Orientation is extracted from the
  // quaternion in axis-angle format and must be less than 90 degrees.
  if (std::abs(Angle(query.q.inverse() * train.q)) > kMaxRotation) {
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
    const Eigen::Matrix<float, 3, 3> F = (query.P * query.R) * (train.P * train.R).inverse();
    matches.erase(std::remove_if(
      matches.begin(),
      matches.end(),
      [&query, &train, &F](const cv::DMatch &m)
      {
        const auto &p0 = query.keypoints[m.queryIdx].pt;
        const auto &p1 = train.keypoints[m.trainIdx].pt;

        // Project the feature point from the current image onto the other image
        // using the rotation matrices obtained from gyroscope measurements.
        const auto proj = F * Eigen::Matrix<float, 3, 1>(p0.x, train.bgr.rows - p0.y - 1, 1);
        const auto px = proj.x() / proj.z();
        const auto py = query.bgr.rows - proj.y() / proj.z() - 1;

        // Measure the pixel distance between the points.
        const float dist = std::sqrt((p1.x - px) * (p1.x - px) + (p1.y - py) * (p1.y - py));

        // Ensure the distance does not exceed a certain threshold.
        return dist > kMaxReprojThreshold;
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
  }

  // Build the graph of matching features.
  MatchGraph graph;
  for (const auto &match : robustMatches) {
    graph[{query.index, match.queryIdx}].emplace_back(train.index, match.trainIdx);
  }
  return graph;
}


std::vector<std::pair<cv::Mat, float>>  EnvironmentBuilder::Composite() {
  GroupMatches();
  Optimize();
  return Project();
}


void EnvironmentBuilder::Optimize() {

  // Create the residual blocks based on pairwise matches.
  ceres::Problem problem;
  for (size_t i = 0; i < groups_.size(); ++i) {
    for (const auto &n0 : groups_[i]) {
      for (const auto &n1 : groups_[i]) {
        if (n0.first == n1.first) {
          continue;
        }
        frames_[n0.first].optimized = frames_[n1.first].optimized = true;

        const auto &pt0 = frames_[n0.first].keypoints[n0.second].pt;
        const auto &pt1 = frames_[n1.first].keypoints[n1.second].pt;

        problem.AddResidualBlock(
            new ceres::AutoDiffCostFunction<RayAlignCost, 3, 4, 4>(new RayAlignCost(
                Eigen::Matrix<double, 2, 1>(pt0.x, pt0.y),
                Eigen::Matrix<double, 2, 1>(pt1.x, pt1.y),
                frames_[n0.first].P.cast<double>(),
                frames_[n1.first].P.cast<double>()
            )),
            nullptr,
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
  options.max_num_iterations = 10;
  options.gradient_tolerance = 1e-3;
  options.function_tolerance = 1e-3;
  options.minimizer_progress_to_stdout = true;
  ceres::Solve(options, &problem, &summary);
  std::cerr << summary.FullReport() << std::endl;
}

void EnvironmentBuilder::GroupMatches() {

  // Group the nodes by finding connected components using a depth first search.
  std::unordered_set<std::pair<int, int>, PairHash> visited;
  std::function<void(
      std::vector<std::pair<int, int>> &group,
      const std::pair<int, int> &node)> dfs;
  dfs = [&] (std::vector<std::pair<int, int>> &group, const std::pair<int, int> &node)
  {
    if (visited.find(node) != visited.end()) {
      return;
    }

    visited.insert(node);
    group.push_back(node);
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

  // Remove groups that are too small.
  groups_.erase(std::remove_if(
      groups_.begin(),
      groups_.end(),
      [] (std::vector<std::pair<int, int>> &group) {
          return group.size() < kMinGroupSize;
      }),
      groups_.end()
  );
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
    Project(
        frame.bgr,
        frame.P * frame.q.toRotationMatrix().cast<float>(),
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

  for (int r = 0; r < dstC.rows; ++r) {
    for (int c = 0; c < dstC.cols; ++c) {
      // Projective texturing.
      const float phi = M_PI * (0.5f - static_cast<float>(r) / static_cast<float>(dstC.rows));
      const float theta = static_cast<float>(dstC.cols - c - 1) / static_cast<float>(dstC.cols) * M_PI * 2;
      const Eigen::Matrix<float, 3, 1> p = P * Eigen::Matrix<float, 3, 1>(
          cos(phi) * cos(theta),
          cos(phi) * sin(theta),
          sin(phi)
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
