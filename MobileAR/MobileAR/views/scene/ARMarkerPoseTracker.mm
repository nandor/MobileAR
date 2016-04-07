// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "ARMarkerPoseTracker.h"
#import "UIImage+cvMat.h"
#import "MobileAR-Swift.h"

#include <opencv2/opencv.hpp>
#include <Eigen/Eigen>

#include "ar/KalmanFilter.h"


/// Size of the tracked pattern.
static const cv::Size kPatternSize(4, 11);


struct EKFSensorUpdate {
  template<typename S>
  static Eigen::Matrix<S, 7, 1> Update(
      const Eigen::Matrix<S, 7, 1> &x,
      const Eigen::Matrix<S, 7, 1> &w,
      S dt)
  {
    Eigen::Quaternion<S> q(x(3), x(0), x(1), x(2));
    Eigen::Quaternion<S> r(S(0), x(4) * dt, x(5) * dt, x(6) * dt);
    
    q = q * r;
    
    Eigen::Matrix<S, 7, 1> y;
    y(0) = q.x();
    y(1) = q.y();
    y(2) = q.z();
    y(3) = q.w();
    y(4) = x(4);
    y(5) = x(5);
    y(6) = x(6);
    return y + w;
  }
  
  template<typename S>
  static Eigen::Matrix<S, 7, 1> Measure(
      const Eigen::Matrix<S, 7, 1> &x,
      const Eigen::Matrix<S, 7, 1> &w)
  {
    Eigen::Quaternion<S> q(x(3), x(0), x(1), x(2));
    
    if (q.norm() > S(1e-7)) {
      q.normalize();
    }
    
    Eigen::Matrix<S, 7, 1> y;
    y(0) = q.x();
    y(1) = q.y();
    y(2) = q.z();
    y(3) = q.w();
    y(4) = x(4);
    y(5) = x(5);
    y(6) = x(6);
    return x + w;
  }
};


@implementation ARMarkerPoseTracker
{
  // OpenCV images & temporary matrices.
  cv::Mat rgba;
  cv::Mat gray;
  cv::Mat rvec;
  cv::Mat tvec;

  // Calibration parameters.
  cv::Mat cmat;
  cv::Mat dmat;

  // Reference grid.
  std::vector<cv::Point3f> grid;
  
  // Rotation quaternion.
  Eigen::Quaternion<float> R;
  // Translation vector.
  Eigen::Matrix<float, 3, 1> T;
  
  // Kalman filter state.
  std::shared_ptr<ar::KalmanFilter<float, 7, 7>> kf_;

  // Timestamp to compute frame times.
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

  // Initialize the timers.
  prevTime = CACurrentMediaTime();
  
  // Initialize the pose.
  R = Eigen::Quaternion<float>(0.0f, 0.0f, 1.0f, 0.0f);
  T = Eigen::Matrix<float, 3, 1>(0.0f, 0.0f, 0.0f);
  
  Eigen::Matrix<float, 7, 7> q;
  q <<
    0.01, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00,
    0.00, 0.01, 0.00, 0.00, 0.00, 0.00, 0.00,
    0.00, 0.00, 0.01, 0.00, 0.00, 0.00, 0.00,
    0.00, 0.00, 0.00, 0.01, 0.00, 0.00, 0.00,
    0.00, 0.00, 0.00, 0.00, 0.10, 0.00, 0.00,
    0.00, 0.00, 0.00, 0.00, 0.00, 0.10, 0.00,
    0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.10;
  
  Eigen::Matrix<float, 7, 7> p;
  p <<
    1, 0, 0, 0, 0, 0, 0,
    0, 1, 0, 0, 0, 0, 0,
    0, 0, 1, 0, 0, 0, 0,
    0, 0, 0, 1, 0, 0, 0,
    0, 0, 0, 0, 1, 0, 0,
    0, 0, 0, 0, 0, 1, 0,
    0, 0, 0, 0, 0, 0, 1;
  
  Eigen::Matrix<float, 7, 1> x;
  x << 0, 0, 1, 0, 0.1, 0.1, 0.1;
  
  kf_ = std::make_shared<ar::KalmanFilter<float, 7, 7>>(q, x, p);
  
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
  
  // Pass to Eigen.
  Eigen::Matrix<float, 3, 1> t;
  t(0, 0) =  tvec.at<double>(0, 0);
  t(1, 0) = -tvec.at<double>(1, 0);
  t(2, 0) = -tvec.at<double>(2, 0);
  Eigen::Matrix<float, 3, 1> r;
  r(0, 0) =  rvec.at<double>(0, 0);
  r(1, 0) = -rvec.at<double>(1, 0);
  r(2, 0) = -rvec.at<double>(2, 0);
  
  //R = { r.norm(), r.normalized() };
  //T = t;
}

- (void)trackSensor:(CMAttitude *)x a:(CMAcceleration)a w:(CMRotationRate)w
{
  // Compute the delta time since the last update.
  const double time = CACurrentMediaTime();
  const double dt = time - prevTime;
  prevTime = time;
  
  auto qq = [x quaternion];
  R = Eigen::Quaternion<float>(-qq.w, -qq.y, qq.x, qq.z);
  
  Eigen::Matrix<float, 7, 7> r;
  r <<
    0.01, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00,
    0.00, 0.01, 0.00, 0.00, 0.00, 0.00, 0.00,
    0.00, 0.00, 0.01, 0.00, 0.00, 0.00, 0.00,
    0.00, 0.00, 0.00, 0.01, 0.00, 0.00, 0.00,
    0.00, 0.00, 0.00, 0.00, 0.10, 0.00, 0.00,
    0.00, 0.00, 0.00, 0.00, 0.00, 0.10, 0.00,
    0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.10;
  
  Eigen::Matrix<float, 7, 1> z;
  z << -qq.y, qq.x, qq.z, -qq.w, w.x, w.y, w.z;
  kf_->Update<EKFSensorUpdate, 7, 7>(dt, z, r);
  
  const auto xx = kf_->GetState();
  Eigen::Quaternion<float> q(xx(3), xx(0), xx(1), xx(2));
  R = q.normalized();
  T(2, 0) = -50.0f;
}

- (ARPose *)getPose
{
  // Extrinsic matrix - translation + rotation.
  const auto r = R.toRotationMatrix();
  
  // Pass the extrinsic matrix.
  NSArray<NSNumber*> *viewMat = @[
      @(r(0, 0)), @(r(1, 0)), @(r(2, 0)), @(0.0f),
      @(r(0, 1)), @(r(1, 1)), @(r(2, 1)), @(0.0f),
      @(r(0, 2)), @(r(1, 2)), @(r(2, 2)), @(0.0f),
      @(T(0, 0)), @(T(1, 0)), @(T(2, 0)), @(1.0f),
  ];
  
  // Pass the intrinsic matrix, converting to OpenGL depth convention.
  const float fx = cmat.at<double>(0, 0);
  const float fy = cmat.at<double>(1, 1);
  const float cx = cmat.at<double>(0, 2);
  const float cy = cmat.at<double>(1, 2);
  const float f = 500.0f;
  const float n = 0.1f;
  
  NSArray<NSNumber*> *projMat = @[
      @(fx / cx),    @(0.0f),                 @(0.0f), @( 0.0f),
         @(0.0f), @(fy / cy),                 @(0.0f), @( 0.0f),
         @(0.0f),    @(0.0f),   @(-(f + n) / (f - n)), @(-1.0f),
         @(0.0f),    @(0.0f), @(-2 * f * n / (f - n)), @( 0.0f)
  ];
  
  // Create the pose out of the view + projection matrix.
  return [[ARPose alloc] initWithViewMat:viewMat projMat:projMat];
}

@end
