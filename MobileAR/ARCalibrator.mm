// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <AVFoundation/AVFoundation.h>

#import "ARCalibrator.h"
#import "UIImage+cvMat.h"
#import "MobileAR-Swift.h"

#include <opencv2/opencv.hpp>


/// Number of snapshots taken for calibration.
static const size_t kCalibrationPoints = 16;

/// Size of the asymetric circle pattern.
static const cv::Size kPatternSize(4, 11);


@implementation ARCalibrator
{
  // OpenCV images.
  cv::Mat gray;
  cv::Mat rgb;
  cv::Mat bgra;

  // Buffer for calibration points.
  std::vector<std::vector<cv::Point2f>> imagePoints;
  std::vector<cv::Point3f> grid;

  // Computed parameters.
  cv::Mat cameraMatrix;
  cv::Mat distCoeffs;
  cv::Mat rvec;
  cv::Mat tvec;

  // Callbacks.
  ARCalibratorProgressCallback onProgress;
  ARCalibratorCompleteCallback onComplete;
}

- (instancetype)init
{
  if (!(self = [super init])) {
    return nil;
  }

  rvec = cv::Mat(3, 1, CV_64F);
  tvec = cv::Mat(3, 1, CV_64F);
  cameraMatrix = cv::Mat::eye(3, 3, CV_64F);
  distCoeffs = cv::Mat::zeros(5, 1, CV_64F);

  // Reserve storage for the point sets.
  imagePoints.reserve(kCalibrationPoints);

  // Initialize the coordinates in the grid pattern.
  for (int i = 0; i < kPatternSize.height; i++ ) {
    for (int j = 0; j < kPatternSize.width; j++) {
      grid.emplace_back((2 * j + i % 2) * 1.0f, i * 1.0f, 0.0f);
    }
  }

  return self;
}

- (UIImage*)findPattern:(UIImage*)frame
{
  [frame toCvMat:bgra];
  cv::cvtColor(bgra, rgb, CV_BGRA2RGB);
  cv::cvtColor(rgb, gray, CV_RGB2GRAY);

  // Find the chessboard.
  std::vector<cv::Point2f> corners;
  auto found = cv::findCirclesGrid(
      gray,
      kPatternSize,
      corners,
      cv::CALIB_CB_ASYMMETRIC_GRID | cv::CALIB_CB_CLUSTERING
  );
  if (!found) {
    return frame;
  }

  // Draw the detected pattern.
  cv::drawChessboardCorners(rgb, kPatternSize, cv::Mat(corners), found);
  if (imagePoints.size() >= kCalibrationPoints) {
    return [UIImage imageWithCvMat:rgb];
  }

  // Add the point to the set of calibration points and report progress.
  imagePoints.push_back(corners);
  if (onProgress) {
    onProgress(static_cast<float>(imagePoints.size()) / kCalibrationPoints);
  }

  // If enough points were recorded, start calibrating in a backgroud thread.
  if (imagePoints.size() == kCalibrationPoints) {
    // Otherwise, calibrate in a background thread.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      double rms = cv::calibrateCamera(
          { grid },
          imagePoints,
          rgb.size(),
          cameraMatrix,
          distCoeffs,
          {},
          {},
          0
      );

      if (onComplete) {
        auto params = [[ARParameters alloc]
            initWithFx: cameraMatrix.at<double>(0, 0)
                    fy: cameraMatrix.at<double>(1, 1)
                    cx: cameraMatrix.at<double>(0, 2)
                    cy: cameraMatrix.at<double>(1, 2)
                    k1: distCoeffs.at<double>(0, 0)
                    k2: distCoeffs.at<double>(1, 0)
                    k3: distCoeffs.at<double>(4, 0)
                    r1: distCoeffs.at<double>(2, 0)
                    r2: distCoeffs.at<double>(3, 0)];
      }
    });
  }

  return [UIImage imageWithCvMat:rgb];
}

- (void)onProgress:(ARCalibratorProgressCallback)callback
{
  onProgress = callback;
}

- (void)onComplete:(ARCalibratorCompleteCallback)callback
{
  onComplete = callback;
}

@end