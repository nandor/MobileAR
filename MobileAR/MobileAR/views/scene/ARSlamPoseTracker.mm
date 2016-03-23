// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "ARSlamPoseTracker.h"
#import "UIImage+cvMat.h"
#import "MobileAR-Swift.h"

#include <memory>

#include "lsd/SlamSystem.h"



@implementation ARSlamPoseTracker
{
  /// Reference to the SLAM system.
  std::shared_ptr<lsd_slam::SlamSystem> odometry;
  /// RGBA image passed to the tracker.
  cv::Mat rgba;
  /// Grayscale image passed to SLAM.
  cv::Mat gray;
  /// Image counter.
  unsigned counter;
}

- (instancetype)initWithParameters:(ARParameters *)params
{
  if (!(self = [super init])) {
    return nil;
  }
  
  cv::Mat K(3, 3, CV_32F);
  K.at<float>(0, 0) = params.fx;
  K.at<float>(1, 1) = params.fy;
  K.at<float>(2, 2) = 1.0f;
  K.at<float>(0, 2) = params.cx;
  K.at<float>(1, 2) = params.cy;
  
  cv::Mat d(4, 1, CV_32F);
  d.at<float>(0) = params.k1;
  d.at<float>(1) = params.k2;
  d.at<float>(2) = params.r1;
  d.at<float>(3) = params.r2;
  
  cv::Mat P = cv::getOptimalNewCameraMatrix(K, d, {640, 360}, 0, {640, 320});
  
  // Intrinsic camera parameters.
  Sophus::Matrix3f K_sophus;
  K_sophus <<
      P.at<float>(0, 0), P.at<float>(0, 1), P.at<float>(0, 2),
      P.at<float>(1, 0), P.at<float>(1, 1), P.at<float>(1, 2),
      P.at<float>(2, 0), P.at<float>(2, 1), P.at<float>(2, 2);
  
  
  // SLAM system.
  odometry = std::make_shared<lsd_slam::SlamSystem>(640, 320, K_sophus, true);
  counter = 0;

  return self;
}

- (UIImage*)trackFrame:(UIImage *)image
{
  [image toCvMat: rgba];
  cv::cvtColor(rgba(cv::Rect(0, 20, 640, 320)), gray, CV_BGRA2GRAY);
  
  if (++counter == 1) {
		odometry->randomInit(gray.data, time(0), 1);
  } else {
    odometry->trackFrame(gray.data, counter, false, time(0));
  }
  
  return [UIImage imageWithCvMat:gray];
}

- (void)trackSensor:(CMAttitude *)attitude acceleration:(CMAcceleration)acceleration
{
}

- (ARPose *)getPose
{
  return nil;
}
@end