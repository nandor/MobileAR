// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include "EnvironmentBuilder.h"

namespace ar {

namespace {

constexpr float kMinBlurThreshold = 0.01f;
constexpr size_t kMinFeatures = 100;
constexpr size_t kMinMatches = 25;
constexpr float kMaxHammingDistance = 30;
constexpr float kMaxReprojDistance = 75.0f;
constexpr float kMaxRotation = 25.0f * M_PI / 180.0f;

}


EnvironmentBuilder::EnvironmentBuilder(
    size_t width,
    size_t height,
    const cv::Mat &k,
    const cv::Mat &d,
    bool undistort)
  : width_(width)
  , height_(height)
  , undistort_(undistort)
  , orbDetector_()
  , blurDetector_(new BlurDetector(360, 640))
{
  assert(k.rows == 3 && k.cols == 3);
  assert(d.rows == 4 && d.cols == 1);

  matcher_ = std::make_unique<cv::BFMatcher>(cv::NORM_HAMMING, true);
  cv::initUndistortRectifyMap(k, d, {}, k, {640, 360}, CV_16SC2, mapX_, mapY_);
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

      // Invert Y to change coordinate systems.
      for (auto &kp : keypoints) {
        kp.pt.y = bgr.rows - kp.pt.y - 1;
      }

      // Get the rotation quaternion.
      frames.emplace_back(
          i,
          bgr,
          keypoints,
          descriptors,
          frame.R,
          frame.P,
          Eigen::Quaternion<float>(frame.R)
      );
    }
  }

  /*

  // Number of different images this frame is matched to & number of matches.
  size_t pairs = 0;

  for (size_t j = 0; j < frames_.size(); ++j) {
    const auto &frame = frames_[j];

    // Threshold by relative orientation. Orientation is extracted from the
    // quaternion in axis-angle format and must be less than 30 degrees.
    {
      const float angle = 2.0f * std::acos((q.inverse() * frame.q).w());
      if (angle > kMaxRotation) {
        continue;
      }
    }

    // Find ORB matches and make sure there are enough of them.
    std::vector<cv::DMatch> matches;
    matcher_->match(frame.descriptors, descriptors, matches);
    if (matches.size() < kMinMatches) {
      continue;
    }

    // Threshold by Hamming distance.
    {
      std::sort(
          matches.begin(),
          matches.end(),
          [](const cv::DMatch &a, const cv::DMatch &b)
          {
            return a.distance < b.distance;
          }
      );
      const auto maxHamming = std::min(kMaxHammingDistance, matches[0].distance * 5);
      matches.erase(std::remove_if(
          matches.begin(),
          matches.end(),
          [maxHamming](const cv::DMatch &m)
          {
            return m.distance > maxHamming;
          }),
          matches.end()
      );

      if (matches.size() < kMinMatches) {
        continue;
      }
    }

    // Threshold by reprojection error, removing unlikely matches.
    {
      const Eigen::Matrix<float, 3, 3> F = P * R * (frame.P * frame.R).inverse();
      matches.erase(std::remove_if(
          matches.begin(),
          matches.end(),
          [&keypoints, &frame, &F](const cv::DMatch &m)
          {
            const auto &p0 = keypoints[m.trainIdx].pt;
            const auto &p1 = frame.keypoints[m.queryIdx].pt;

            // Project the feature point from the current image onto the other image
            // using the rotation matrices obtained from gyroscope measurements.
            const auto proj = F * Eigen::Matrix<float, 3, 1>(p0.x, p0.y, 1);
            const auto px = proj.x() / proj.z();
            const auto py = proj.y() / proj.z();

            // Measure the pixel distance between the points.
            const float dist = std::sqrt(
                (p1.x - px) * (p1.x - px) + (p1.y - py) * (p1.y - py)
            );

            // Ensure the distance does not exceed a certain threshold.
            return dist > kMaxReprojDistance;
          }),
          matches.end()
      );

      if (matches.size() < kMinMatches) {
        continue;
      }
    }

    // Find a homography between the two using RANSAC & LMeDS, removing
    // all matches that are not included in the RANSAC estimation.
    std::vector<cv::DMatch> finalMatches;
    {
      std::vector<cv::Point2f> src, dst;
      cv::Mat mask;
      for (const auto &match : matches) {
        src.push_back(keypoints[match.trainIdx].pt);
        dst.push_back(frame.keypoints[match.queryIdx].pt);
      }
      cv::findHomography(src, dst, CV_LMEDS, 2.0f, mask);
      if (matches.size() != mask.rows) {
        continue;
      }
      for (int i = 0; i < mask.rows; ++i) {
        if (mask.at<bool>(i, 0)) {
          finalMatches.push_back(matches[i]);
        }
      }
      if (finalMatches.size() < kMinMatches) {
        continue;
      }
    }
    
    // If all the tests passed, count the pair as a match.
    pairs += 1;
  }
  
  // Decide whether the new image is to be merged into the panorama.
  // A frame is good if it matches at least 3 other frames (or at least one other
  // if less than 5 frames are available to ensure that the start frames are good).
  if (frames_.size() != 0 && ((frames_.size() < 5) ? (pairs <= 0) : (pairs <= 2))) {
    throw EnvironmentBuilderException(EnvironmentBuilderException::NO_MATCHES);
  }
  
  // Add the frame to the frame list.
  frames_.emplace_back(bgr, keypoints, descriptors, P, R, q);
  */
}
  
}
