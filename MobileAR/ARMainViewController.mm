// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "ARCamera.h"
#import "ARMainViewController.h"
#import "ARRenderer.h"
#import "UIImage+cvMat.h"

#include <stdexcept>
#include <vector>

namespace {

/**
 Number of snapshots taken for calibration.
 */
const size_t kCalibrationPoints = 15;
  
/**
 Size of the asymetric circle pattern.
 */
const cv::Size kPatternSize(4, 11);

}

enum class State {
  CAPTURE,
  CALIBRATE,
  AUGMENT
};


@implementation ARMainViewController
{
  // UI elements.
  UIImageView *imageView;
  UIProgressView *progressView;
  UIActivityIndicatorView *spinnerView;
  UILabel *textView;
  
  // Submodules.
  ARRenderer *renderer;
  ARCamera *camera;
  
  // Application state.
  State state;
  
  // OpenCV images.
  cv::Mat gray, rgb;
  
  // Buffer for calibration points.
  std::vector<std::vector<cv::Point2f>> imagePoints;
  std::vector<cv::Point3f> grid;
  cv::Mat cameraMatrix;
  cv::Mat distCoeffs;
}


/**
 Called when the view is loaded.
 */
- (void)viewDidLoad
{
  [super viewDidLoad];
  [self setupView];
  
  renderer = [[ARRenderer alloc] init];
  
  // Initialize the camera.
  camera = [[ARCamera alloc] initWithCallback:^(cv::Mat mat) {
    [self onFrameCallback:mat];
  }];
  
  // Start capturing images for calibration.
  state = State::CAPTURE;
  imagePoints.reserve(kCalibrationPoints);
  
  // Initialize the OpenCV grid.
  for (int i = 0; i < kPatternSize.height; i++ ) {
    for (int j = 0; j < kPatternSize.width; j++) {
      grid.emplace_back((2 * j + i % 2) * 1.0f, i * 1.0f, 0.0f);
    }
  }
}


- (void)viewDidAppear:(BOOL)animated
{
  [camera startRecording];
}


- (void)viewWillDisappear:(BOOL)animated
{
  [camera stopRecording];
}


/**
 Receives a frame from the camera.
 */
- (void)onFrameCallback:(cv::Mat)bgra
{
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
  
  switch (state) {
    case State::CAPTURE: {
      if (imagePoints.size() != kCalibrationPoints) {
        if (found) {
          imagePoints.push_back(corners);
          cv::drawChessboardCorners(rgb, kPatternSize, cv::Mat(corners), found);
        }
        dispatch_sync(dispatch_get_main_queue(), ^{
          [spinnerView setHidden:YES];
          [progressView setHidden:NO];
          progressView.progress = static_cast<float>(imagePoints.size()) / kCalibrationPoints;
          textView.text = @"Capturing data";
        });
      } else {
        state = State::CALIBRATE;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
          cameraMatrix = cv::Mat::eye(3, 3, CV_64F);
          distCoeffs = cv::Mat::zeros(4, 1, CV_64F);
          
          std::vector<cv::Mat> rvecs, tvecs;
          float rms = cv::calibrateCamera(
              std::vector<std::vector<cv::Point3f>>(kCalibrationPoints, grid),
              imagePoints,
              rgb.size(),
              cameraMatrix,
              distCoeffs,
              rvecs,
              tvecs,
              0
          );
          
          NSLog(@"RMS: %f", rms);
          state = State::AUGMENT;
        });
      }
      break;
    }
    case State::CALIBRATE: {
      dispatch_sync(dispatch_get_main_queue(), ^{
        [spinnerView setHidden:NO];
        [progressView setHidden:YES];
        textView.text = @"Calibrating";
      });
      break;
    }
    case State::AUGMENT: {
      dispatch_sync(dispatch_get_main_queue(), ^{
        [spinnerView setHidden:YES];
        [progressView setHidden:YES];
        [textView setHidden:YES];
      });
      
      if (found) {
        cv::Mat rvec(3, 1, CV_64F);
        cv::Mat tvec(3, 1, CV_64F);
        cv::Mat rvecR(3, 1, CV_64F);
        
        cv::solvePnP(grid, corners, cameraMatrix, distCoeffs, rvec, tvec);
        cv::Rodrigues(rvec, rvecR);

        std::vector<cv::Point2d> points;
        std::vector<cv::Point3d> objectPoints{cv::Point3d(3.0, 3.0, 0.0)};
        
        cv::projectPoints(
            objectPoints,
            rvec,
            tvec,
            cameraMatrix,
            distCoeffs,
            points
        );
        auto point = points[0];
        cv::circle(rgb, points[0], 10, cv::Scalar(255, 0, 0));
      }
      
      break;
    }
  }

  auto image = [UIImage imageWithCvMat:rgb];
  dispatch_async(dispatch_get_main_queue(), ^{
    [imageView setImage:image];
  });
}


/**
 Sets up the UI elements.
 */
- (void)setupView
{
  auto frame = self.view.frame;
  
  // Create an image in the center.
  {
    CGRect imageRect;
    imageRect.size.height = frame.size.height;
    imageRect.size.width = frame.size.height * 640.0f / 480.0f;
    imageRect.origin.x = (frame.size.width - imageRect.size.width) /2;
    imageRect.origin.y = 0;
    imageView = [[UIImageView alloc] initWithFrame:imageRect];
    [self.view addSubview:imageView];
  }
  
  // Progress bar on top of the image.
  {
    CGRect progressRect;
    progressRect.size.width = 100;
    progressRect.size.height = 0;
    progressRect.origin.x = (frame.size.width - progressRect.size.width) / 2;
    progressRect.origin.y = (frame.size.height - progressRect.size.height) / 2;
    progressView = [[UIProgressView alloc] initWithFrame:progressRect];
    [self.view addSubview:progressView];
  }
  
  // Spinner shown during calibration.
  {
    CGRect spinnerRect;
    spinnerRect.size.width = 20;
    spinnerRect.size.height = 20;
    spinnerRect.origin.x = (frame.size.width - spinnerRect.size.width) / 2;
    spinnerRect.origin.y = (frame.size.height - spinnerRect.size.height) / 2;
    spinnerView = [[UIActivityIndicatorView alloc] initWithFrame:spinnerRect];
    [self.view addSubview:spinnerView];
  }
  
  // Text view indicating status.
  {
    CGRect textRect;
    textRect.size.width = 200;
    textRect.size.height = 20;
    textRect.origin.x = (frame.size.width - textRect.size.width) / 2;
    textRect.origin.y = (frame.size.height - textRect.size.height) / 2 + 20;
    textView = [[UILabel alloc] initWithFrame:textRect];
    textView.textColor = [UIColor whiteColor];
    textView.textAlignment = NSTextAlignmentCenter;
    textView.text = @"";
    [self.view addSubview:textView];
  }
  
  [spinnerView startAnimating];
}

@end
