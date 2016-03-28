// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "ARSlamPoseTracker.h"
#import "UIImage+cvMat.h"
#import "MobileAR-Swift.h"

#include <atomic>
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
  /// Undistorted image.
  cv::Mat undistorted;
  /// Image counter.
  unsigned counter;
  
  /// Original camera matrix.
  cv::Mat K0;
  /// Cropped camera matrix.
  cv::Mat K1;
  /// Distortion parameters.
  cv::Mat d;
  /// Undistort map 1.
  cv::Mat map1;
  /// Unfistort map 2.
  cv::Mat map2;
  
  /// Queue on which tracking is executed.
  dispatch_queue_t queue;
  /// Number of queued frames.
  std::atomic<int> queued;
}

- (instancetype)initWithParameters:(ARParameters *)params
{
  if (!(self = [super init])) {
    return nil;
  }
  
  // Initializes the undistort map.
  K0 = cv::Mat::zeros(3, 3, CV_32F);
  K0.at<float>(0, 0) = params.fx;
  K0.at<float>(1, 1) = params.fy;
  K0.at<float>(2, 2) = 1.0f;
  K0.at<float>(0, 2) = params.cx;
  K0.at<float>(1, 2) = params.cy;
  
  d = cv::Mat::zeros(4, 1, CV_32F);
  d.at<float>(0) = params.k1;
  d.at<float>(1) = params.k2;
  d.at<float>(2) = params.r1;
  d.at<float>(3) = params.r2;
  
  K1 = cv::getOptimalNewCameraMatrix(K0, d, {640, 360}, 0, {640, 320});
  cv::initUndistortRectifyMap(K0, d, {}, K1, {640, 320}, CV_16SC2, map1, map2);
  
  // Initialize the queue which executes tracking.
  queue = dispatch_queue_create("ic.ac.uk.LSD_SLAM", DISPATCH_QUEUE_SERIAL);
  queued = 0;
  
  // Intrinsic camera parameters.
  Sophus::Matrix3f K_sophus;
  K_sophus <<
      K1.at<float>(0, 0), K1.at<float>(0, 1), K1.at<float>(0, 2),
      K1.at<float>(1, 0), K1.at<float>(1, 1), K1.at<float>(1, 2),
      K1.at<float>(2, 0), K1.at<float>(2, 1), K1.at<float>(2, 2);
  
  
  // SLAM system.
  odometry = std::make_shared<lsd_slam::SlamSystem>(640, 320, K_sophus, true);
  counter = 0;

  return self;
}

- (void)trackFrame:(UIImage *)image
{
  if (++queued >= 3) {
    --queued;
    return;
  }
  
  // Crop, convert and undistort the image.
  dispatch_async(queue, ^{
    [image toCvMat: rgba];
    cv::cvtColor(rgba(cv::Rect(0, 20, 640, 320)), gray, CV_BGRA2GRAY);
    cv::remap(gray, undistorted, map1, map2, cv::INTER_LINEAR);
  
    // Pass the image onto LSD SLAM, returning the last pose.
    if (++counter == 1) {
      odometry->randomInit(undistorted.data, time(0), 1);
    } else {
      odometry->trackFrame(undistorted.data, counter, false, time(0));
    }
    
    --queued;
  });
}

- (void)trackSensor:(CMAttitude *)x a:(CMAcceleration)a w:(CMRotationRate)w
{
}

- (ARPose *)getPose
{
  return nil;
}
@end