// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "AREnvironmentBuilder.h"
#import "UIImage+cvMat.h"
#import "MobileAR-Swift.h"

#include <opencv2/opencv.hpp>
#include <simd/simd.h>


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

  return self;
}


- (void)update:(UIImage*)image pose:(ARPose*)pose {
  [image toCvMat: frame];
  
  std::vector<cv::KeyPoint> keypoints;
  
  cv::cvtColor(frame, gray, CV_BGR2GRAY);
  auto detector = cv::FastFeatureDetector::create(50);
  detector->detect(gray, keypoints);
  
  for (const auto &keypoint : keypoints) {
    cv::circle(frame, keypoint.pt, 3, { 255, 0, 255 });
  }
  
  for (int r = 0; r < frame.rows; ++r) {
    auto ptr = frame.ptr<cv::Vec4b>(r);
    for (int c = 0; c < frame.cols; ++c) {
      // Cast a ray through the pixel.
      const auto ray = simd::normalize(-simd::float3([pose unproject: {
          static_cast<float>(frame.cols - c - 1),
          static_cast<float>(r),
          1.0f,
      }]));

      // Project it onto the unit sphere & compute UV.
      const auto l = static_cast<float>(simd::length(ray));
      const auto u = static_cast<float>(atan2(ray.x, ray.y) / (2 * M_PI));
      const auto v = static_cast<float>(acos(ray.z / l) / M_PI);

      // Compute texture coordinate, wrap around.
      const auto fx = (static_cast<int>(preview.cols * u) + preview.cols) % preview.cols;
      const auto fy = (static_cast<int>(preview.rows * v) + preview.rows) % preview.rows;

      // Write the preview image.
      preview.at<cv::Vec4b>(fy, fx) = cv::Vec4b(ptr[c][2], ptr[c][1], ptr[c][0], 0xFF);
    }
  }
}


- (UIImage*)getPreview {
  return [UIImage imageWithCvMat: preview];
}

@end