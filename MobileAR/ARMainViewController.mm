// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

#import "ARMainViewController.h"
#import "UIImage+cvMat.h"

#include <stdexcept>
#include <vector>


@implementation ARMainViewController
{
  // Camera capture with an AV session.
  AVCaptureSession *captureSession;
  AVCaptureDevice *videoCaptureDevice;
  AVCaptureDeviceInput *videoInput;
  AVCaptureVideoDataOutput *videoOutput;
  
  // Synchronisation stuff.
  dispatch_queue_t queue;
  
  // Image view where output is displayed.
  UIImageView *imageView;
  
  // OpenCV images.
  cv::Mat gray, rgb, bgra;
}


/**
 Called when the view is loaded.
 */
- (void)viewDidLoad
{
  [super viewDidLoad];
  [self setupCamera];
  
  CGRect rect = self.view.frame;
  rect.size.width = rect.size.height * 640.0f / 480.0f;
  imageView = [[UIImageView alloc] initWithFrame:rect];
  [self.view addSubview:imageView];
}


- (void)viewDidAppear:(BOOL)animated
{
  [captureSession startRunning];
}


- (void)viewWillDisappear:(BOOL)animated
{
  [captureSession stopRunning];
}


/**
 Receives a frame from the camera.
 */
- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
  bgra = [self matrixFromSampleBuffer: sampleBuffer];
  
  cv::cvtColor(bgra, rgb, CV_BGRA2RGB);
  cv::cvtColor(rgb, gray, CV_RGB2GRAY);
  
  // Find the chessboard.
  std::vector<cv::Point2f> corners;
  const cv::Size size(4, 11);
  
  auto found = cv::findCirclesGrid(gray, size, corners, cv::CALIB_CB_ASYMMETRIC_GRID | cv::CALIB_CB_CLUSTERING);
  cv::drawChessboardCorners(rgb, size, cv::Mat(corners), found);
  
  auto image = [UIImage imageWithCvMat:rgb];
  dispatch_async(dispatch_get_main_queue(), ^{
    [imageView setImage:image];
  });
}


/**
 Sets up the camera.
 */
- (void)setupCamera
{
  try {
    NSError *error = nil;
    
    // Open the camera for video playback.
    videoCaptureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!videoCaptureDevice) {
      throw std::runtime_error("Cannot capture video output.");
    }
    if ([videoCaptureDevice lockForConfiguration:nil]) {
      videoCaptureDevice.activeVideoMaxFrameDuration = CMTimeMake(1, 15);
      [videoCaptureDevice unlockForConfiguration];
    }
    
    videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoCaptureDevice error:&error];
    if (!videoInput) {
      throw std::runtime_error([[error localizedDescription] UTF8String]);
    }
    
    // Capture raw image from the camera through the output object.
    videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    if (!videoOutput) {
      throw std::runtime_error("Cannot capture video output.");
    }
    queue = dispatch_queue_create("MobileAR", DISPATCH_QUEUE_SERIAL);
    [videoOutput setSampleBufferDelegate:(id)self queue:queue];
    videoOutput.videoSettings = @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)
    };
    
    
    // Create a new capture session.
    captureSession = [[AVCaptureSession alloc] init];
    if (!captureSession) {
      throw std::runtime_error("Cannot open capture session.");
    }
    captureSession.sessionPreset = AVCaptureSessionPresetMedium;
    [captureSession addInput:videoInput];
    [captureSession addOutput:videoOutput];
  } catch (const std::exception &ex) {
    [self alert:@(ex.what())];
  }
}


/**
 Create a UIImage from sample buffer data.
 */
- (cv::Mat)matrixFromSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
  cv::Mat mat;
  
  // Lock on the buffer & copy data.
  auto imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
  CVPixelBufferLockBaseAddress(imageBuffer, 0);
  {
    mat = cv::Mat(
        cv::Size(
            static_cast<int>(CVPixelBufferGetWidth(imageBuffer)),
            static_cast<int>(CVPixelBufferGetHeight(imageBuffer))
        ),
        CV_8UC4,
        CVPixelBufferGetBaseAddress(imageBuffer),
        CVPixelBufferGetBytesPerRow(imageBuffer));
  }
  CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
  
  return mat;
}


/**
 Displays an alert with a message.
 */
- (void)alert:(NSString * const)message
{
  UIAlertController *alertController = [UIAlertController
      alertControllerWithTitle: @"Error"
      message: message
      preferredStyle: UIAlertControllerStyleAlert
  ];
  [alertController addAction:[UIAlertAction
      actionWithTitle: @"Exit"
      style: UIAlertActionStyleDefault
      handler:^(UIAlertAction *) {
          exit(0);
      }
  ]];
  [self presentViewController:alertController animated:YES completion:nil];}

@end
