// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "AREnvironmentBuilder.h"
#import "UIImage+cvMat.h"
#import "MobileAR-Swift.h"

#include <unordered_map>

#include <ceres/ceres.h>
#include <opencv2/opencv.hpp>
#include <simd/simd.h>


#include "ar/Rotation.h"


/// Minimum number of features and matches required for tracking.
static constexpr size_t kMinFeatures = 100;
static constexpr size_t kMinMatches = 25;
static constexpr float kMaxHammingDistance = 30;
static constexpr float kMaxReprojDistance = 75.0f;
static constexpr float kMaxRotation = 25.0f * M_PI / 180.0f;


/**
 Converts a SIMD matrix to an Eigen matrix.
 */
template<typename T>
Eigen::Matrix<T, 3, 3> ToEigen(const simd::float4x4 &m) {
  return (Eigen::Matrix<T, 3, 3>() <<
      T(m.columns[0].x), T(m.columns[1].x), T(m.columns[2].x),
      T(m.columns[0].y), T(m.columns[1].y), T(m.columns[2].y),
      T(m.columns[0].z), T(m.columns[1].z), T(m.columns[2].z)
  ).finished();
}

/**
 Converts an Eigen matrix to a SIMD matrix.
 */
simd::float4x4 ToSIMD(const Eigen::Matrix<float, 3, 3> &r) {
  return simd::float4x4(
      simd::float4{ r(0, 0), r(1, 0), r(2, 0), 0.0f },
      simd::float4{ r(0, 1), r(1, 1), r(2, 1), 0.0f },
      simd::float4{ r(0, 2), r(1, 2), r(2, 2), 0.0f },
      simd::float4{    0.0f,    0.0f,    0.0f, 1.0f }
  );
}


/**
 Information collected from a single frame.
 */
struct Frame {
  // RGB version.
  const cv::Mat bgr;
  // List of keypoints.
  const std::vector<cv::KeyPoint> keypoints;
  // List of ORB descriptors.
  const cv::Mat descriptors;
  // Intrinsic matrix.
  const simd::float4x4 P;
  // Extrinsic matrix (Camera pose).
  const simd::float4x4 R;
  // Quaternion rotation.
  const Eigen::Quaternionf q;
  
  Frame(
    const cv::Mat &bgr,
    const std::vector<cv::KeyPoint> &keypoints,
    const cv::Mat &descriptors,
    const simd::float4x4 &P,
    const simd::float4x4 &R,
    const Eigen::Quaternionf &q)
    : bgr(bgr)
    , keypoints(keypoints)
    , descriptors(descriptors)
    , P(P)
    , R(R)
    , q(q)
  {
  }
};


@implementation AREnvironmentBuilder
{
  // Width of the environment map.
  size_t width;
  // Height of the environment map.
  size_t height;

  // List of processed frames.
  std::vector<Frame> frames;
  
  // Distortion maps.
  cv::Mat map1;
  cv::Mat map2;

  // Keypoint detctor & matcher.
  cv::Ptr<cv::ORB> detector;
  std::unique_ptr<cv::BFMatcher> matcher;
}


- (instancetype)initWithParams:(ARParameters *)params width:(size_t)width_ height:(size_t)height_
{
  if (!(self = [super init])) {
    return nil;
  }

  // Initialize the detector & feature matchers.
  {
    width = width_;
    height = height_;
    detector = cv::ORB::create();
    matcher = std::make_unique<cv::BFMatcher>(cv::NORM_HAMMING, true);
  }
  
  // Initialize the undistort maps.
  {
    cv::Mat k = cv::Mat::zeros(3, 3, CV_32F);
    k.at<float>(0, 0) = params.fx;
    k.at<float>(1, 1) = params.fy;
    k.at<float>(2, 2) = 1.0f;
    k.at<float>(0, 2) = params.cx;
    k.at<float>(1, 2) = params.cy;
    cv::Mat d = cv::Mat::zeros(4, 1, CV_32F);
    d.at<float>(0) = params.k1;
    d.at<float>(1) = params.k2;
    d.at<float>(2) = params.r1;
    d.at<float>(3) = params.r2;
  
    cv::initUndistortRectifyMap(k, d, {}, k, {640, 360}, CV_16SC2, map1, map2);
  }
  
  return self;
}

- (BOOL)update:(UIImage*)image pose:(ARPose*)pose {
  
  // Fetch both the RGB and the grayscale versions of the frame.
  cv::Mat bgr, gray;
  [image toCvMat: bgr];
  cv::remap(bgr, bgr, map1, map2, cv::INTER_LINEAR);
  cv::cvtColor(bgr, gray, CV_BGR2GRAY);
  
  // Extract ORB features & descriptors and make sure we have enough of them.
  std::vector<cv::KeyPoint> keypoints;
  cv::Mat descriptors;
  detector->detectAndCompute(gray, {}, keypoints, descriptors);
  if (keypoints.size() < kMinFeatures) {
    return NO;
  }
  
  // Invert Y to change coordinate systems.
  for (auto &kp : keypoints) {
    kp.pt.y = bgr.rows - kp.pt.y - 1;
  }
  
  // Extract intrinsic & extrinsic matrices from pose.
  const simd::float4x4 P  = [pose proj];
  P.columns[2].y = bgr.rows - P.columns[2].y - 1;
  const simd::float4x4 R  = [pose view];
  
  // Extract the rotation component and store it in a quaternion.
  Eigen::Quaternionf q(ToEigen<float>(R));
  
  // Graph mapping indices of features in the current frame
  // with a list of frames and features in those frames.
  typedef std::unordered_map<int, std::vector<std::pair<int, Eigen::Vector3d>>> MatchGraph;
  MatchGraph G;
  
  // Number of different images this frame is matched to & number of matches.
  size_t pairs = 0;
  int residuals = 0;
  
  for (size_t j = 0; j < frames.size(); ++j) {
    const auto &frame = frames[j];
    
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
    matcher->match(frame.descriptors, descriptors, matches);
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
      const auto F = P * R * simd::inverse(frame.P * frame.R);
      matches.erase(std::remove_if(
          matches.begin(),
          matches.end(),
          [&keypoints, &frame, &F](const cv::DMatch &m)
          {
            const auto &p0 = keypoints[m.trainIdx].pt;
            const auto &p1 = frame.keypoints[m.queryIdx].pt;
      
            // Project the feature point from the current image onto the other image
            // using the rotation matrices obtained from gyroscope measurements.
            const auto proj = F * simd::float4{ p0.x, p0.y, 1, 0 };
            const auto px = proj.x / proj.z;
            const auto py = proj.y / proj.z;
       
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
    simd::float4x4 H;
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
    
    // Add points to the graph. Note that Y is inverted since the rotation matrix
    // is in world frame where Y points...somewhere
    if (pairs == 0) {
    for (const auto &m : finalMatches) {
      const auto &pt = frame.keypoints[m.queryIdx].pt;
      G[m.trainIdx].emplace_back(j, Eigen::Vector3d(pt.x, pt.y, 1));
    }
      residuals += finalMatches.size();
    }
     
    // If all the tests passed, count the pair as a match.
    pairs += 1;
  }
  
  // Decide whether the new image is to be merged into the panorama.
  // A frame is good if it matches at least 3 other frames (or at least one other
  // if less than 5 frames are available to ensure that the start frames are good).
  if (frames.size() != 0 && ((frames.size() < 5) ? (pairs <= 0) : (pairs <= 2))) {
    return NO;
  }
  
  // Add the frame to the frame list.
  frames.emplace_back(bgr, keypoints, descriptors, P, R, q);
  return YES;
}


@end
