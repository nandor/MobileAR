// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "AREnvironmentBuilder.h"
#import "UIImage+cvMat.h"
#import "MobileAR-Swift.h"

#include <opencv2/opencv.hpp>
#include <simd/simd.h>


#include "ar/Rotation.h"


/// Minimum number of features and matches required for tracking.
static constexpr size_t kMinFeatures = 100;
static constexpr size_t kMinMatches = 25;
static constexpr float kMaxHammingDistance = 30;
static constexpr float kMaxReprojDistance = 75.0f;
static constexpr float kMaxRotation = 30.0f * M_PI / 180.0f;

/**
 Information collected from a single frame.
 */
struct Frame {
  // RGB version.
  const cv::Mat bgr;
  // Grayscale version.
  const cv::Mat gray;
  // List of keypoints.
  const std::vector<cv::KeyPoint> keypoints;
  // List of ORB descriptors.
  const cv::Mat descriptors;
  // Intrinsic matrix.
  const simd::float4x4 P;
  // Extrinsic matrix (Camera pose).
  const simd::float4x4 R;
  
  Frame(
    const cv::Mat &bgr,
    const cv::Mat &gray,
    const std::vector<cv::KeyPoint> &keypoints,
    const cv::Mat &descriptors,
    const simd::float4x4 &P,
    const simd::float4x4 &R)
    : bgr(bgr)
    , gray(gray)
    , keypoints(keypoints)
    , descriptors(descriptors)
    , P(P)
    , R(R)
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

  // Keypoint detctor & matcher.
  cv::Ptr<cv::ORB> detector;
  std::unique_ptr<cv::BFMatcher> matcher;
}


- (instancetype)initWithWidth:(size_t)width_ height:(size_t)height_
{
  if (!(self = [super init])) {
    return nil;
  }

  width = width_;
  height = height_;

  detector = cv::ORB::create();
  matcher = std::make_unique<cv::BFMatcher>(cv::NORM_HAMMING, true);

  return self;
}

- (ARPose*)update:(UIImage*)image pose:(ARPose*)pose {
  
  // Fetch both the RGB and the grayscale versions of the frame.
  cv::Mat bgr, gray;
  [image toCvMat: bgr];
  cv::cvtColor(bgr, gray, CV_BGR2GRAY);
  
  // Extract ORB features & descriptors and make sure we have enough of them.
  std::vector<cv::KeyPoint> keypoints;
  cv::Mat descriptors;
  detector->detectAndCompute(gray, {}, keypoints, descriptors);
  if (keypoints.size() < kMinFeatures) {
    return nil;
  }
  
  // Extract intrinsic & extrinsic matrices from pose.
  const simd::float4x4 P  = [pose proj];
  const simd::float4x4 R  = [pose view];
  const simd::float4x4 iR = simd::inverse(R);
  
  // Ensure that the current image matches at least some other images.
  size_t pairs = 0;
  for (const auto &frame : frames) {
    
    // Threshold by relative orientation. Orientation is extracted from the
    // rotation matrix in axis-angle format and must be less than 30 degrees.
    {
      const simd::float4x4 r = iR * frame.R;
      Eigen::Matrix<float, 3, 3> er;
      er <<
        r.columns[0].x, r.columns[1].x, r.columns[2].x,
        r.columns[0].y, r.columns[1].y, r.columns[2].y,
        r.columns[0].z, r.columns[1].z, r.columns[2].z;
      const float angle = 2.0f * std::acos(Eigen::Quaternionf(er).w());
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
            const auto proj = F * simd::float4{ p0.x, frame.bgr.rows - p0.y - 1, 1, 0 };
            const auto px = proj.x / proj.z;
            const auto py = frame.bgr.rows - proj.y / proj.z - 1;
       
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
     
    // If all the tests passed, count the pair as a match.
    ++pairs;
  }
  
  // Decide whether the new image is to be merged into the panorama.
  // A frame is good if it matches at least 3 other frames (or at least one other
  // if less than 5 frames are available to ensure that the start frames are good).
  if (frames.size() != 0 && ((frames.size() < 5) ? (pairs <= 0) : (pairs <= 2))) {
    return nil;
  }
  
  // Add the frame to the frame list.
  frames.emplace_back(bgr, gray, keypoints, descriptors, P, R);
  return pose;
}


@end
