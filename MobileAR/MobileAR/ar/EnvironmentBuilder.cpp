// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include "EnvironmentBuilder.h"

namespace ar {

namespace {

constexpr float kMinBlurThreshold = 0.01f;
constexpr size_t kMinFeatures = 100;
constexpr size_t kMinMatches = 30;
constexpr float kRansacReprojError = 5.0;
constexpr float kMaxHammingDistance = 20;
constexpr float kMaxReprojThreshold = 5.0f;
constexpr float kMaxReprojRotation = 10.0f * M_PI / 180.0f;
constexpr float kMaxRotation = 60.0f * M_PI / 180.0f;

}


EnvironmentBuilder::EnvironmentBuilder(
    size_t width,
    size_t height,
    const cv::Mat &k,
    const cv::Mat &d,
    bool undistort)
  : width_(width)
  , height_(height)
  , index_(0)
  , undistort_(undistort)
  , blurDetector_(new BlurDetector(720, 1280))
  , orbDetector_(500)
  , bfMatcher_(cv::NORM_HAMMING, true)
{
  assert(k.rows == 3 && k.cols == 3);
  assert(d.rows == 4 && d.cols == 1);

  cv::initUndistortRectifyMap(k, d, {}, k, {1280, 720}, CV_16SC2, mapX_, mapY_);
}


void EnvironmentBuilder::AddFrames(const std::vector<HDRFrame> &rawFrames) {

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
      {
        float per, blur;
        std::tie(per, blur) = (*blurDetector_)(gray);
        if (per < kMinBlurThreshold) {
          //throw EnvironmentBuilderException(EnvironmentBuilderException::BLURRY);
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
          index_++,
          i,
          bgr,
          keypoints,
          descriptors,
          frame.P,
          frame.R,
          Eigen::Quaternion<float>(frame.R)
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
  for (const auto &frame : frames) {

    // Save all the match graphs to other images.
    std::vector<MatchGraph> pairs;
    for (size_t i = 0; i < frames_.size(); ++i) {
      const auto &match = Match(frames_[i], frame);
      if (match.empty()) {
        continue;
      }
      pairs.emplace_back(match);
    }

    // If not enough matches are avialble, bail out.
    if (frames_.size() != 0 && pairs.size() <= ((frames_.size() < 5) ? 0 : 2)) {
      throw EnvironmentBuilderException(EnvironmentBuilderException::NO_GLOBAL_MATCHES);
    }

    std::copy(pairs.begin(), pairs.end(), std::back_inserter(matches));
  }

  // Add the frames to the buffer.
  std::copy(frames.begin(), frames.end(), std::back_inserter(frames_));

  // Merge the graphs.
  for (const auto &graph : matches) {
    for (const auto &node : graph) {
      std::copy(node.second.begin(), node.second.end(), std::back_inserter(graph_[node.first]));
    }
  }
}

EnvironmentBuilder::MatchGraph EnvironmentBuilder::Match(
    const Frame &train,
    const Frame &query)
{

  // Threshold by relative orientation. Orientation is extracted from the
  // quaternion in axis-angle format and must be less than 90 degrees.
  const float angle = 2.0f * std::acos((query.q.inverse() * train.q).w());
  if (angle > kMaxRotation) {
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
  if (angle < kMaxReprojRotation) {
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
    if (robustMatches.size() < kMinMatches) {
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
  
}
