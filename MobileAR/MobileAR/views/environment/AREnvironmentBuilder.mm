// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "AREnvironmentBuilder.h"
#import "UIImage+cvMat.h"
#import "MobileAR-Swift.h"

#include <opencv2/opencv.hpp>
#include <simd/simd.h>


/// Minimum number of features and matches required for tracking.
static constexpr size_t kMinFeatures = 100;
static constexpr size_t kMinMatches = 25;
static constexpr float kMaxHammingDistance = 30;
static constexpr float kMaxReprojDistance = 75.0f;

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

  // OpenCV matrix holding the map.
  cv::Mat preview;
  // OpenCV matrix holding a composited preview.
  cv::Mat composited;

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
  preview = cv::Mat::zeros(
      static_cast<int>(height),
      static_cast<int>(width),
      CV_8UC4
  );
  composited = cv::Mat::zeros(
      static_cast<int>(height),
      static_cast<int>(width),
      CV_8UC4
  );

  detector = cv::ORB::create();
  matcher = std::make_unique<cv::BFMatcher>(cv::NORM_HAMMING, true);

  return self;
}

- (BOOL)update:(UIImage*)image pose:(ARPose*)pose {
  
  // Fetch both the RGB and the grayscale versions of the frame.
  cv::Mat bgr, gray;
  [image toCvMat: bgr];
  cv::cvtColor(bgr, gray, CV_BGR2GRAY);
  
  // Extract ORB features & descriptors and make sure we have enough of them.
  std::vector<cv::KeyPoint> keypoints;
  cv::Mat descriptors;
  detector->detectAndCompute(gray, {}, keypoints, descriptors);
  if (keypoints.size() < kMinFeatures) {
    return NO;
  }
  
  // Extract intrinsic & extrinsic matrices from pose.
  const simd::float4x4 P = [pose proj];
  const simd::float4x4 R = [pose view];
  
  // Ensure that the current image matches at least some other images.
  size_t pairs = 0;
  for (const auto &frame : frames) {
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
      const cv::Mat h = cv::findHomography(src, dst, CV_LMEDS, 2.0f, mask);
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
      
      // Convert the homography to a 'normal' format.
      H = simd::float4x4(
          simd::float4{ h.at<float>(0, 0), h.at<float>(1, 0), h.at<float>(2, 0), 0 },
          simd::float4{ h.at<float>(0, 1), h.at<float>(1, 1), h.at<float>(2, 1), 0 },
          simd::float4{ h.at<float>(0, 2), h.at<float>(1, 2), h.at<float>(2, 2), 0 },
          simd::float4{                 0,                 0,                 0, 1 }
      );
    }
     
    // If all the tests passed, count the pair as a match.
    ++pairs;
  }
  
  // Decide whether the new image is to be merged into the panorama.
  // A frame is good if it matches at least 3 other frames (or at least one other
  // if less than 5 frames are available to ensure that the start frames are good).
  bool merge = frames.size() == 0 || ((frames.size() < 5) ? (pairs > 0) : (pairs > 2));
  
  // Add the frame to the list.
  if (merge) {
    frames.emplace_back(bgr, gray, keypoints, descriptors, P, R);
  }
  
  // Project the image onto the environment map.
  preview.copyTo(composited);
  for (int r = 0; r < bgr.rows; ++r) {
    auto ptr = bgr.ptr<cv::Vec4b>(r);
    for (int c = 0; c < bgr.cols; ++c) {
      // Cast a ray through the pixel.
      const auto pr = simd::inverse(P * R) * simd::float4{
          static_cast<float>(bgr.cols - c - 1),
          static_cast<float>(r),
          1.0f,
          1.0f,
      };
      const auto wr = simd::normalize(-simd::float3{pr.x, pr.y, pr.z} / pr.w);

      // Project it onto the unit sphere & compute UV.
      const auto u = static_cast<float>(atan2(wr.x, wr.y) / (2 * M_PI));
      const auto v = static_cast<float>(acos(wr.z) / M_PI);

      // Compute texture coordinate, wrap around.
      const auto fx = (static_cast<int>(preview.cols * u) + preview.cols) % preview.cols;
      const auto fy = (static_cast<int>(preview.rows * v) + preview.rows) % preview.rows;
      
      const cv::Vec4b pix(ptr[c][2], ptr[c][1], ptr[c][0], 0xFF);
      
      // If image not to be merge, do not add it to preview.
      if (merge) {
        preview.at<cv::Vec4b>(fy, fx) = pix;
      }
      
      // Otherwise, show a red border and add a red tint to the image on the composite.
      if (c < 5 || r < 5 || c > bgr.cols - 5 || r > bgr.rows - 5) {
        composited.at<cv::Vec4b>(fy, fx) = cv::Vec4b(0, 0, 0xFF, 0xFF);
      } else {
        composited.at<cv::Vec4b>(fy, fx) = pix + cv::Vec4b(0, 0, merge ? 0 : 50, 0xFF);
      }
    }
  }
  
  return merge;
}

- (UIImage*)getPreview {
  return [UIImage imageWithCvMat: composited];
}

@end
