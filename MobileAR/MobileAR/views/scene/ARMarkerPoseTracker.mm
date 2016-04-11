// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "ARMarkerPoseTracker.h"
#import "UIImage+cvMat.h"
#import "MobileAR-Swift.h"

#include <opencv2/opencv.hpp>
#include <Eigen/Eigen>
#include <Eigen/SVD>

#include "ar/KalmanFilter.h"


/// Size of the tracked pattern.
static const cv::Size kPatternSize(4, 11);
/// Number of measurements to consider for the computation of the relative pose.
static const size_t kRelativePoses = 25;
/// Gravitational acceleration, in cm/s^2.
static const float kGravity = 9.806 * 100;


/**
 Computes the average quaternion.
 */
template<typename T>
Eigen::Quaternion<T> average(const std::vector<Eigen::Quaternion<T>> &qis) {
  
  // Much math leads here.
  Eigen::Matrix<T, 4, 4> M = Eigen::Matrix<T, 4, 4>::Zero();
  for (const auto &qi : qis) {
    Eigen::Matrix<T, 4, 1> qv;
    qv << qi.x(), qi.y(), qi.z(), qi.w();
    M += qv * qv.transpose();
  }
  
  // Compute the SVD of the matrix.
  Eigen::JacobiSVD<Eigen::Matrix<T, 4, 4>> svd(M, Eigen::ComputeFullU | Eigen::ComputeFullV);
  const auto q = svd.matrixU().col(0);
  return Eigen::Quaternion<T>(q(3), q(0), q(1), q(2));
}


struct EKFUpdate {
  template<typename S>
  static Eigen::Matrix<S, 19, 1> Update(
      const Eigen::Matrix<S, 19, 1> &x,
      const Eigen::Matrix<S, 19, 1> &w,
      S dt)
  {
    // Extract rotation data from the state.
    Eigen::Quaternion<S> rq(x(3), x(0), x(1), x(2));
    Eigen::Matrix<S, 3, 1> rv(x(4), x(5), x(6));
    Eigen::Matrix<S, 3, 1> ra(x(7), x(8), x(9));
    
    // Extract position data from the state.
    Eigen::Matrix<S, 3, 1> xx(x(10), x(11), x(12));
    Eigen::Matrix<S, 3, 1> xv(x(13), x(14), x(15));
    Eigen::Matrix<S, 3, 1> xa(x(16), x(17), x(18));
    
    // Transform the acceleration vector to the body frame.
    const auto a = rq.normalized().inverse().toRotationMatrix() * xa * S(kGravity);
    
    // Update position and velocity.
    xx = xx + xv * dt + a * dt * dt / S(2.0);
    xv = xv + a * dt / S(2.0);
    
    // Update the angular velocity and the rotation.
    Eigen::Matrix<S, 3, 1> r = S(0.5) * (rv * dt + ra * dt * dt / S(2));
    rv = rv + ra * dt;
    rq = rq * Eigen::Quaternion<S>(S(0), r(0), r(1), r(2));
    
    // Repack data into the state vector.
    Eigen::Matrix<S, 19, 1> y;
    y( 0) = rq.x(); y( 1) = rq.y(); y( 2) = rq.z(); y( 3) = rq.w();
    y( 4) = rv(0); y( 5) = rv(1); y( 6) = rv(2);
    y( 7) = ra(0); y( 8) = ra(1); y( 9) = ra(2);
    y(10) = xx(0); y(11) = xx(1); y(12) = xx(2);
    y(13) = xv(0); y(14) = xv(1); y(15) = xv(2);
    y(16) = xa(0); y(17) = xa(1); y(18) = xa(2);
    return y + w;
  }
};

struct EKFSensorUpdate : public EKFUpdate {
  template<typename S>
  static Eigen::Matrix<S, 10, 1> Measure(
      const Eigen::Matrix<S, 19, 1> &x,
      const Eigen::Matrix<S, 10, 1> &w)
  {
    Eigen::Matrix<S, 10, 1> y;
    y(0) = x( 0); y(1) = x( 1); y(2) = x( 2); y(3) = x(3);
    y(4) = x( 4); y(5) = x( 5); y(6) = x( 6);
    y(7) = x(16); y(8) = x(17); y(9) = x(18);
    return y + w;
  }
};

struct EKFMarkerUpdate : public EKFUpdate {
  template<typename S>
  static Eigen::Matrix<S, 7, 1> Measure(
      const Eigen::Matrix<S, 19, 1> &x,
      const Eigen::Matrix<S, 7, 1> &w)
  {
    Eigen::Matrix<S, 7, 1> y;
    y(0) = x( 0); y(1) = x( 1); y(2) = x( 2); y(3) = x(3);
    y(4) = x(10); y(5) = x(11); y(6) = x(12);
    return y + w;
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
  std::shared_ptr<ar::KalmanFilter<float, 19, 19>> kf_;

  // Timestamp to compute frame times.
  double prevTime;
  
  // List of relative orientations, measured between the world and marker frame.
  std::vector<Eigen::Quaternion<float>> relativePoses;
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
  
  {
    // Process noise covariance.
    Eigen::Matrix<float, 19, 1> q;
    q <<
      0.01, 0.01, 0.01, 0.01,
      0.10, 0.10, 0.10,
      0.20, 0.20, 0.20,
      1.00, 1.00, 1.00,
      1.00, 1.00, 1.00,
      1.00, 1.00, 1.00;
  
    // Initial process noise.
    Eigen::Matrix<float, 19, 1> p;
    p <<
      10, 10, 10, 10,
      10, 10, 10,
      10, 10, 10,
      10, 10, 10,
      10, 10, 10,
      10, 10, 10;
    
    // Initial state.
    Eigen::Matrix<float, 19, 1> x;
    x <<
      0, 0, 1, 0,
      0, 0, 0,
      0, 0, 0,
      0, 0, 0,
      0, 0, 0,
      0, 0, 0;
    
    // Initialize the Kalman filter.
    kf_ = std::make_shared<ar::KalmanFilter<float, 19, 19>>(q.asDiagonal(), x, p.asDiagonal());
  }
  
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
  
  // Convert to a quaternion.
  Eigen::Quaternion<float> q;
  q = { r.norm(), r.normalized() };
  
  // Limit the size of the pose buffer.
  if (relativePoses.size() > kRelativePoses) {
    relativePoses.erase(relativePoses.begin(), relativePoses.begin() + 1);
  }
  
  // Find the average orientation between the marker frame and the world frame.
  if (relativePoses.size() > 0) {
    
    // Find the world rotation, as provided by the marker.
    Eigen::Quaternion<float> relativePose = average<float>(relativePoses);
    Eigen::Quaternion<float> wq = q * relativePose;
    
    // Measurement noise matrix.
    Eigen::Matrix<float, 7, 1> r;
    r << 0.01, 0.01, 0.01, 0.01, 3.0, 3.0, 3.0;
    
    // Update the Kalman filter with position.
    Eigen::Matrix<float, 7, 1> z;
    z << wq.x(), wq.y(), wq.z(), wq.w(), t(0), t(1), t(2);
    kf_->Update<EKFMarkerUpdate, 7, 7>([self deltaTime], z, r.asDiagonal());
  
    // Read out the quaternion & update the pose.
    const auto xx = kf_->GetState();
    Eigen::Quaternion<float> q(xx(3), xx(0), xx(1), xx(2));
    R = q.normalized();
    T = { xx(10), xx(11), xx(12) };
  }
  
  relativePoses.push_back(q.inverse() * R);
}


- (void)trackSensor:(CMAttitude *)x a:(CMAcceleration)a w:(CMRotationRate)w
{
  // Measurement noise matrix.
  Eigen::Matrix<float, 10, 1> r;
  r << 0.01, 0.01, 0.01, 0.01, 0.10, 0.10, 0.10, 2.00, 2.00, 2.00;
  
  // Update with the quaternion & angular velocity.
  const auto qq = [x quaternion];
  Eigen::Matrix<float, 10, 1> z;
  z << -qq.y, qq.x, qq.z, -qq.w, w.x, w.y, w.z, a.x, a.y, a.z;
  kf_->Update<EKFSensorUpdate, 10, 10>([self deltaTime], z, r.asDiagonal());
  
  // Read out the quaternion & update the pose.
  const auto xx = kf_->GetState();
  Eigen::Quaternion<float> q(xx(3), xx(0), xx(1), xx(2));
  R = q.normalized();
  T = { xx(10), xx(11), xx(12) };
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

/**
 Computes the time since the last update.
 */
- (double)deltaTime
{
  const double time = CACurrentMediaTime();
  const double dt = time - prevTime;
  prevTime = time;
  return dt;
}

@end
