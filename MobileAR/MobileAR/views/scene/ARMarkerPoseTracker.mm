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
static const size_t kRelativePoses = 50;


/**
 Computes the average quaternion.
 */
template<typename T>
Eigen::Quaternion<T> average(const std::vector<Eigen::Quaternion<T>> &qis) {
  
  // Much math leads here.
  Eigen::Matrix<T, 4, 4> M = Eigen::Matrix<T, 4, 4>::Zero();
  for (const auto &qi : qis) {
    Eigen::Matrix<T, 4, 1> qv(qi.x(), qi.y(), qi.z(), qi.w());
    M += qv * qv.transpose();
  }
  
  // Compute the SVD of the matrix.
  Eigen::JacobiSVD<Eigen::Matrix<T, 4, 4>> svd(M, Eigen::ComputeFullU | Eigen::ComputeFullV);
  const auto q = svd.matrixU().col(0);
  return Eigen::Quaternion<T>(q(3), q(0), q(1), q(2));
}


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
  std::shared_ptr<ar::EKFOrientation<double>> kf_;

  // Timestamp to compute frame times.
  double prevTime;
  
  // List of relative orientations, measured between the world and marker frame.
  std::vector<Eigen::Quaternion<double>> relativePoses;
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
  T = Eigen::Matrix<float, 3, 1>(0.0f, 0.0f, -50.0f);
    
  // Initialize the Kalman filter.
  kf_ = std::make_shared<ar::EKFOrientation<double>>();
  
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
    Eigen::Quaternion<double> relativePose = average(relativePoses);
    
    // Update the filter.
    kf_->UpdateMarker(q.cast<double>() * relativePose, [self deltaTime]);
    R = kf_->GetOrientation().cast<float>();
    T = t;
  }
  
  relativePoses.push_back((q.inverse() * R).cast<double>());
}


- (void)trackSensor:(CMAttitude *)x a:(CMAcceleration)a w:(CMRotationRate)w
{
  // Update the filter.
  const auto qq = [x quaternion];
  kf_->UpdateIMU(
      Eigen::Quaternion<double>(-qq.w, -qq.y, qq.x, qq.z),
      Eigen::Matrix<double, 3, 1>(w.x, w.y, w.z),
      [self deltaTime]
  );
  
  // Update object pose.
  R = kf_->GetOrientation().cast<float>();
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
