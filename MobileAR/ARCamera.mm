// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

#import "ARCamera.h"

@implementation ARCamera
{
  // AV Capture objects.
  AVCaptureSession *captureSession;
  AVCaptureDevice *videoCaptureDevice;
  AVCaptureDeviceInput *videoInput;
  AVCaptureVideoDataOutput *videoOutput;
  
  // Queue to run the camera on.
  dispatch_queue_t queue;
  
  // Callback block.
  void (^callback)(cv::Mat);
  
  // OpenCV matrix.
  cv::Mat mat;
}

- (id)initWithCallback:(void(^)(cv::Mat))block;
{
  if (!block || !(self = [super init])) {
    return nil;
  }
  
  NSError *error = nil;
  
  // Open the camera for video playback.
  videoCaptureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
  if (!videoCaptureDevice) {
    return nil;
  }
  if ([videoCaptureDevice lockForConfiguration:nil]) {
    videoCaptureDevice.activeVideoMaxFrameDuration = CMTimeMake(1, 15);
    [videoCaptureDevice unlockForConfiguration];
  }
  
  videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoCaptureDevice error:&error];
  if (!videoInput) {
    return nil;
  }
  
  // Capture raw image from the camera through the output object.
  videoOutput = [[AVCaptureVideoDataOutput alloc] init];
  if (!videoOutput) {
    return nil;
  }
  queue = dispatch_queue_create("MobileAR", DISPATCH_QUEUE_SERIAL);
  [videoOutput setSampleBufferDelegate:(id)self queue:queue];
  videoOutput.videoSettings = @{
    (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)
  };
    
  
  // Create a new capture session.
  captureSession = [[AVCaptureSession alloc] init];
  if (!captureSession) {
    return nil;
  }
  captureSession.sessionPreset = AVCaptureSessionPresetMedium;
  [captureSession addInput:videoInput];
  [captureSession addOutput:videoOutput];
  
  // Set the callback.
  callback = block;
  
  return self;
}


/**
 Frame record callback.
 */
- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
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
        CVPixelBufferGetBytesPerRow(imageBuffer)
    );
  }
  CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
  
  // Execute the callback.
  @autoreleasepool { callback(mat); }
}


/**
 Starts recording frames.
 */
- (void)start
{
  [captureSession startRunning];
}


/**
 Stops recording frames.
 */
- (void)stop
{
  [captureSession stopRunning];
}

@end
