// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "ARCamera.h"
#import "ARCalibrateController.h"
#import "ARRenderer.h"
#import "UIImage+cvMat.h"

#include <stdexcept>
#include <vector>

namespace {

/**
 Number of snapshots taken for calibration.
 */
const size_t kCalibrationPoints = 16;
  
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


@implementation ARCalibrateController
{
  // UI elements.
  UIProgressView *progressView;
  UIActivityIndicatorView *spinnerView;
  UILabel *textView;
  UIImageView *mainView;
  
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
  
  cv::Mat rvec;
  cv::Mat tvec;
}


/**
 Initializes the controller.
 */
- (id)init
{
  if (!(self = [super init])) {
    return nil;
  }
  
  // Initialize matrices.
  rvec = cv::Mat(3, 1, CV_32F);
  tvec = cv::Mat(3, 1, CV_32F);
  cameraMatrix = cv::Mat::eye(3, 3, CV_32F);
  distCoeffs = cv::Mat::zeros(4, 1, CV_32F);

  // Reserve storage for the point sets.
  imagePoints.reserve(kCalibrationPoints);
  
  // Initialize the OpenCV grid.
  for (int i = 0; i < kPatternSize.height; i++ ) {
    for (int j = 0; j < kPatternSize.width; j++) {
      grid.emplace_back((2 * j + i % 2) * 1.0f, i * 1.0f, 0.0f);
    }
  }
  
  return self;
}


/**
 Called when the view is loaded.
 */
- (void)viewDidLoad
{
  [super viewDidLoad];
  
  [self setupView];
  
  // Initialize the Metal renderer.
  renderer = [[ARRenderer alloc] initWithView:mainView];
  
  // Initialize the camera.
  camera = [[ARCamera alloc] initWithCallback:^(cv::Mat mat) {
    [self onFrameCallback:mat];
  }];
  
  // Start capturing images for calibration.
  state = State::CAPTURE;

  // Set the title.
  self.title = @"Calibrate";
}

- (void) viewWillAppear:(BOOL) animated
{
  [super viewWillAppear: animated];

  [self.navigationController setNavigationBarHidden: NO animated: animated];
  self.navigationController.hidesBarsOnSwipe = YES;

}

- (void)viewDidAppear:(BOOL)animated
{
  [super viewDidAppear:animated];

  [camera start];
  [renderer start];
}


- (void)viewWillDisappear:(BOOL)animated
{
  [super viewWillDisappear:animated];
  
  [renderer stop];
  [camera stop];
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
          cameraMatrix = cv::Mat::eye(3, 3, CV_32F);
          distCoeffs = cv::Mat::zeros(4, 1, CV_32F);
          
          std::vector<cv::Mat> rvecs, tvecs;
          double rms = cv::calibrateCamera(
              std::vector<std::vector<cv::Point3f>>(kCalibrationPoints, grid),
              imagePoints,
              rgb.size(),
              cameraMatrix,
              distCoeffs,
              rvecs,
              tvecs,
              0
          );
          cameraMatrix.convertTo(cameraMatrix, CV_32F);
          distCoeffs.convertTo(distCoeffs, CV_32F);
          
          NSLog(@"RMS: %g", rms);
          NSLog(@"%g %g %g %g", cameraMatrix.at<float>(0, 0), cameraMatrix.at<float>(1, 1), cameraMatrix.at<float>(0, 2), cameraMatrix.at<float>(1, 2));
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
        cv::solvePnP(grid, corners, cameraMatrix, distCoeffs, rvec, tvec);
        rvec.convertTo(rvec, CV_32F);
        tvec.convertTo(tvec, CV_32F);
      }
      
      break;
    }
  }
  
  cv::cvtColor(rgb, bgra, CV_RGB2BGRA);
  [renderer update:bgra K:cameraMatrix r:rvec t:tvec d:distCoeffs];
}


/**
 Sets up the UI elements.
 */
- (void)setupView
{
  auto frame = self.view.frame;
  
  // Create an image in the center.
  {
    CGRect mainRect;
    mainRect.size.height = frame.size.height;
    mainRect.size.width = frame.size.height * 480.0f / 360.0f;
    mainRect.origin.x = (frame.size.width - mainRect.size.width) /2;
    mainRect.origin.y = 0;
    mainView = [[UIImageView alloc] initWithFrame:mainRect];
    [self.view addSubview:mainView];
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
