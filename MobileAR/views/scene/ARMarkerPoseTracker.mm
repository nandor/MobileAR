// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "ARMarkerPoseTracker.h"
#import "UIImage+cvMat.h"
#import "MobileAR-Swift.h"

#include <opencv2/opencv.hpp>
#include <Eigen/Eigen>


/**
 Size of the tracked pattern.
 */
static const cv::Size kPatternSize(4, 11);


@implementation ARMarkerPoseTracker
{
  // OpenCV images.
  cv::Mat rgba;
  cv::Mat gray;

  // Calibration parameters.
  cv::Mat cmat;
  cv::Mat dmat;

  // Reference grid.
  std::vector<cv::Point3f> grid;

  // Camera pose.
  cv::Mat rvec;
  cv::Mat tvec;
  cv::Mat rmat;
  
  // Last frame timestamp.
  double prevTime;
}

- (instancetype)initWithParameters:(ARParameters *)params
{
  if (!(self = [super init])) {
    return nil;
  }

  // Set up the intrinsic matrix.
  cmat = cv::Mat::zeros(3, 3, CV_64F);
  cmat.at<double>(0, 0) = params.fx;
  cmat.at<double>(1, 1) = params.fy;
  cmat.at<double>(0, 2) = params.cx;
  cmat.at<double>(1, 2) = params.cy;
  cmat.at<double>(2, 2) = 1.0f;

  // Set up the distortion parameters.
  dmat = cv::Mat::zeros(4, 1, CV_64F);
  dmat.at<double>(0, 0) = params.k1;
  dmat.at<double>(1, 0) = params.k2;
  dmat.at<double>(2, 0) = params.r1;
  dmat.at<double>(3, 0) = params.r2;

  // Initialize the coordinates in the grid pattern.
  for (int i = 0; i < kPatternSize.height; i++ ) {
    for (int j = 0; j < kPatternSize.width; j++) {
      grid.emplace_back((2 * j + i % 2) * 4.0f, i * 4.0f, 0.0f);
    }
  }

  rvec = cv::Mat::zeros(3, 1, CV_64F);
  tvec = cv::Mat::zeros(3, 1, CV_64F);
  rmat = cv::Mat::zeros(3, 3, CV_64F);

  // Initialize the timer.
  prevTime = CACurrentMediaTime();
  
  return self;
}


- (void)trackFrame:(UIImage *)image
{
  [image toCvMat:rgba];
  cv::cvtColor(rgba, gray, CV_BGRA2GRAY);


  // Detect the pattern.
  std::vector<cv::Point2f> corners;
  auto found = cv::findCirclesGrid(
      gray,
      kPatternSize,
      corners,
      cv::CALIB_CB_ASYMMETRIC_GRID | cv::CALIB_CB_CLUSTERING
  );
  if (!found) {
    return;
  }

  // If pattern found, use solvePnP to compute pose.
  cv::solvePnP({ grid }, corners, cmat, dmat, rvec, tvec);
  cv::Rodrigues(rvec, rmat);
}


- (void)trackSensor:(CMAttitude *)attitude acceleration:(CMAcceleration)acceleration
{
  // Compute time difference and clamp to 1FPS or more.
  const double currTime = CACurrentMediaTime();
  const double dt1 = (currTime - prevTime > 1.0) ? 0.0 : (currTime - prevTime);
  const double dt2 = (dt1 * dt1) / 2.0f;
  prevTime = currTime;
  
  // The state transition matrix A updates the state.
  Eigen::Matrix<double, 9, 9> A;
  A <<
    1.0, 0.0, 0.0, dt1, 0.0, 0.0, dt2, 0.0, 0.0,
    0.0, 1.0, 0.0, 0.0, dt1, 0.0, 0.0, dt2, 0.0,
    0.0, 0.0, 1.0, 0.0, 0.0, dt1, 0.0, 0.0, dt2,
    0.0, 0.0, 0.0, 1.0, 0.0, 0.0, dt1, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, dt1, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, dt1,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0;
  
  // The measurement model relates the state to measurements.
  Eigen::Matrix<double, 3, 9> H;
  H <<
    1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0;
  
  NSLog(@"%g %g %g", acceleration.x, acceleration.y, acceleration.z);
}

- (void)start
{
}


- (void)stop
{
}

- (ARPose *)getPose
{
  NSArray<NSNumber*> *viewMat = @[
      @(rmat.at<double>(0, 0)),
      @(rmat.at<double>(1, 0)),
      @(rmat.at<double>(2, 0)),
      @(0.0f),
      @(rmat.at<double>(0, 1)),
      @(rmat.at<double>(1, 1)),
      @(rmat.at<double>(2, 1)),
      @(0.0f),
      @(rmat.at<double>(0, 2)),
      @(rmat.at<double>(1, 2)),
      @(rmat.at<double>(2, 2)),
      @(0.0f),
      @(tvec.at<double>(0, 0)),
      @(tvec.at<double>(1, 0)),
      @(tvec.at<double>(2, 0)),
      @(1.0f),
  ];

  float fx = cmat.at<double>(0, 0);
  float fy = cmat.at<double>(1, 1);
  float cx = cmat.at<double>(0, 2);
  float cy = cmat.at<double>(1, 2);
  float f = 100.0f;
  float n = 0.1f;

  NSArray<NSNumber*> *projMat = @[
      @(fx / cx),
      @(0.0f),
      @(0.0f),
      @(0.0f),
      
      @(0.0f),
      @(fy / cy),
      @(0.0f),
      @(0.0f),
      
      @(0.0f),
      @(0.0f),
      @(-(f + n) / (f - n)),
      @(-1.0f),
      
      @(0.0f),
      @(0.0f),
      @(-2 * f * n / (f - n)),
      @(0.0f)
  ];

  return [[ARPose alloc] initWithViewMat:viewMat projMat:projMat];
}

@end
