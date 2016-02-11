// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "ARMarkerPoseTracker.h"
#import "UIImage+cvMat.h"
#import "MobileAR-Swift.h"

#include <opencv2/opencv.hpp>
#include <Eigen/Eigen>


/// Size of the tracked pattern.
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

  // Timestamp to compute frame times.
  double prevTime;

  // Kalman filter state.
  Eigen::Matrix<double, 9, 1> X;
  // Covariance.
  Eigen::Matrix<double, 9, 9> P;

  // Process noise.
  Eigen::Matrix<double, 9, 9> Q;
  // Measurement noise.
  Eigen::Matrix<double, 3, 3> Ra;
  // Measurement noise.
  Eigen::Matrix<double, 3, 3> Rt;
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

  // Initialize the timers.
  prevTime = CACurrentMediaTime();

  // Kalman filter process noise.
  Q <<
    0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.1, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.1, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.1;

  // Kalman filter measurement noise.
  Rt <<
    0.50, 0.01, 0.01,
    0.01, 0.50, 0.01,
    0.01, 0.01, 0.50;
  Ra <<
    0.10, 0.01, 0.01,
    0.01, 0.10, 0.01,
    0.01, 0.01, 0.10;

  // Initialize the covariance matrix.
  P <<
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0;

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

  // Compute the time elapsed since last position update.
  const double dt1 = [self deltaTime];
  const double dt2 = dt1 * dt1 / 2.0f;
  
  // Fill in the state transition matrix A with the timestamps.
  // Uses Galilleo's law of motion to update position and velocity
  // given the acceleration: x1 = x0 + v0 * t + a * t * t / 2
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

  // The measurement model extracts the position.
  Eigen::Matrix<double, 3, 9> H;
  H <<
    1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0;
  
  // Convert the position measurement to a vector.
  Eigen::Matrix<double, 3, 1> z;
  z(0, 0) = tvec.at<double>(0, 0);
  z(1, 0) = tvec.at<double>(1, 0);
  z(2, 0) = tvec.at<double>(2, 0);
  
  // Apply the Kalman filter.
  [self kalmanUpdate: z H: H A: A R: Rt];
}

- (void)trackSensor:(CMAttitude *)attitude acceleration:(CMAcceleration)acceleration
{
  // Compute the time elapsed since last acceleration update.
  const double dt1 = [self deltaTime];
  const double dt2 = dt1 * dt1 / 2.0f;
  
  // Fill in the state transition matrix A with the timestamps.
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
  
  // The measurement model extracts the acceleration.
  Eigen::Matrix<double, 3, 9> H;
  H <<
      0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0,
      0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0,
      0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0;
  
  // Convert the position measurement to a vector.
  Eigen::Matrix<double, 3, 1> z;
  z(0, 0) = -acceleration.x * 10;
  z(1, 0) = -acceleration.y * 10;
  z(2, 0) =  acceleration.z * 10;
  
  // Apply the Kalman filter.
  [self kalmanUpdate: z H: H A: A R: Ra];
}

- (void)kalmanUpdate: (const Eigen::Matrix<double, 3, 1>&)z
                   H: (const Eigen::Matrix<double, 3, 9>&)H
                   A: (const Eigen::Matrix<double, 9, 9>&)A
                   R: (const Eigen::Matrix<double, 3, 3>&)R
{
  // Prediction step.
  const auto x = A * X;
  const auto p = A * P * A.transpose() + Q;

  // Update step.
  const auto K = p * H.transpose() * (H * p * H.transpose() + R).inverse();
  X = x + K * (z - H * x);
  P = (Eigen::MatrixXd::Identity(9, 9) - K * H) * p;
}

- (double)deltaTime
{
  const double currTime = CACurrentMediaTime();
  const double dt = currTime - prevTime;
  prevTime = currTime;
  return dt;
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
      @(X(0, 0)),
      @(X(1, 0)),
      @(X(2, 0)),
      @(1.0f),
  ];

  float fx = cmat.at<double>(0, 0);
  float fy = cmat.at<double>(1, 1);
  float cx = cmat.at<double>(0, 2);
  float cy = cmat.at<double>(1, 2);
  float f = 500.0f;
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
