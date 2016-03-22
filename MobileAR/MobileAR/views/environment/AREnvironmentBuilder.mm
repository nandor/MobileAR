// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "AREnvironmentBuilder.h"
#import "UIImage+cvMat.h"
#import "MobileAR-Swift.h"

#include <opencv2/opencv.hpp>
#include <simd/simd.h>


/// Minimum number of features required for tracking.
static constexpr size_t kMinMatches = 20;


@implementation AREnvironmentBuilder
{
  // Width of the environment map.
  size_t width;
  // Height of the environment map.
  size_t height;

  // OpenCV matrix holding the map.
  cv::Mat preview;

  // OpenCV version of the current frame.
  cv::Mat frame;
  // Grayscale version of current frame.
  cv::Mat gray;

  // Number of frames processed.
  size_t count;

  // Keypoint detctor & matcher.
  cv::Ptr<cv::ORB> detector;
  std::unique_ptr<cv::BFMatcher> matcher;

  // Features describing frames.
  std::vector<cv::KeyPoint> kp[2];
  cv::Mat desc[2];

  // Pose of the previous frame.
  simd::float4x4 M;
  simd::float4x4 P;
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

  count = 0;

  detector = cv::ORB::create();
  matcher = std::make_unique<cv::BFMatcher>(cv::NORM_HAMMING);

  return self;
}


- (void)update:(UIImage*)image pose:(ARPose*)pose {
  [image toCvMat: frame];

  // Track the pose using feature mathching on a grayscale image.
  cv::cvtColor(frame, gray, CV_BGR2GRAY);
  if (![self trackPose: pose image: gray]) {
    return;
  }

  // Increment the number of successfully tracked frames.
  ++count;

  // Project the image onto the environment map.
  for (int r = 0; r < frame.rows; ++r) {
    auto ptr = frame.ptr<cv::Vec4b>(r);
    for (int c = 0; c < frame.cols; ++c) {
      // Cast a ray through the pixel.
      const auto pr = simd::inverse(P * M) * simd::float4{
          static_cast<float>(frame.cols - c - 1),
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

      // Write the preview image.
      preview.at<cv::Vec4b>(fy, fx) = cv::Vec4b(ptr[c][2], ptr[c][1], ptr[c][0], 0xFF);
    }
  }
}


- (BOOL)trackPose:(ARPose*)pose image:(const cv::Mat&)image
{
  // Ping-pong between two sets of features.
  size_t i0 = (count + 0) & 1;
  size_t i1 = (count + 1) & 1;
  auto &kp0 = kp[i0], &kp1 = kp[i1];
  auto &ds0 = desc[i0], &ds1 = desc[i1];

  // Detect features & keypoints in the current image.
  detector->detectAndCompute(image, {}, kp1, ds1);
  if (kp0.size() < kMinMatches || kp1.size() < kMinMatches) {
    if (count != 0) {
      return NO;
    }

    P = [pose proj];
    M = [pose view];
    return YES;
  }

  // Match the corresponding features.
  std::vector<cv::DMatch> matches;
  matcher->match(ds0, ds1, matches);
  if (matches.size() <= kMinMatches || count == 0) {
    return NO;
  }

  // Find a homography between the two sets of keypoints.
  std::vector<cv::Point2f> xs0, xs1;
  for (const auto &match: matches) {
    xs0.push_back(kp0[match.queryIdx].pt);
    xs1.push_back(kp1[match.trainIdx].pt);
  }
  
  P = [pose proj];
  M = [pose view];
  
  return YES;
}


- (UIImage*)getPreview {
  return [UIImage imageWithCvMat: preview];
}

@end
