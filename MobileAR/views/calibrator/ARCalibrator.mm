// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <AVFoundation/AVFoundation.h>
#import <CoreLocation/CoreLocation.h>

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
  cv::Mat rgba;

  // Buffer for calibration points.
  std::vector<std::vector<cv::Point2f>> imagePoints;
  std::vector<cv::Point3f> grid;

  // Computed parameters.
  cv::Mat cameraMatrix;
  cv::Mat distCoeffs;

  // Delegate that handles events.
  id<ARCalibratorDelegate> delegate;
}

- (instancetype)initWithDelegate:(id)delegate_
{
  if (!(self = [super init])) {
    return nil;
  }

  delegate = delegate_;

  // Initialize the intrinsic parameters.
  cameraMatrix = cv::Mat::eye(3, 3, CV_64F);
  distCoeffs = cv::Mat::zeros(4, 1, CV_64F);

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
  [frame toCvMat:rgba];
  cv::cvtColor(rgba, rgb, CV_RGBA2RGB);
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
  if ([delegate respondsToSelector:@selector(onProgress:)]) {
    [delegate onProgress:static_cast<float>(imagePoints.size()) / kCalibrationPoints];
  }

  // If enough points were recorded, start calibrating in a backgroud thread.
  if (imagePoints.size() == kCalibrationPoints) {
    // Otherwise, calibrate in a background thread.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      auto rms = static_cast<float>(cv::calibrateCamera(
          std::vector<std::vector<cv::Point3f>>(kCalibrationPoints, grid),
          imagePoints,
          rgb.size(),
          cameraMatrix,
          distCoeffs,
          {},
          {},
          0
      ));
      cameraMatrix.convertTo(cameraMatrix, CV_32F);
      distCoeffs.convertTo(distCoeffs, CV_32F);

      if ([delegate respondsToSelector:@selector(onComplete:params:)]) {
        [delegate onComplete:rms params:[[ARParameters alloc]
            initWithFx: cameraMatrix.at<float>(0, 0)
                    fy: cameraMatrix.at<float>(1, 1)
                    cx: cameraMatrix.at<float>(0, 2)
                    cy: cameraMatrix.at<float>(1, 2)
                    k1: distCoeffs.at<float>(0, 0)
                    k2: distCoeffs.at<float>(1, 0)
                    r1: distCoeffs.at<float>(2, 0)
                    r2: distCoeffs.at<float>(3, 0)]];

      }
    });
  }

  return [UIImage imageWithCvMat:rgb];
}

@end