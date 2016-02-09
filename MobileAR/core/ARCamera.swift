// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import AVFoundation
import CoreImage
import CoreMedia
import UIKit

/**
 Exceptions thrown by the camera.
 */
enum ARCameraError : ErrorType {
  case NotAuthorized
}


/**
 Protocol to handle frames.
 */
protocol ARCameraDelegate {
  func onCameraFrame(frame: UIImage)
}


/**
 Wrapper around AVFoundation camera.
 */
class ARCamera : NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
  
  // Dispatch queue to execute camera code on.
  private let queue = dispatch_queue_create(
      "uk.ac.ic.MobileAR.ARCamera",
      DISPATCH_QUEUE_SERIAL
  )
  
  // Capture session for start/stop.
  internal let captureSession = AVCaptureSession()
  
  // User-specified callback.
  internal var delegate: ARCameraDelegate?
  
  // Camera device.
  internal var device: AVCaptureDevice!
  
  /**
   Iniitalizes the camera wrapper.
   */
  init(delegate: ARCameraDelegate?) throws {
    self.delegate = delegate

    super.init()

    // Try to get access to the default device.
    guard let device = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo) else {
      throw ARCameraError.NotAuthorized
    }
    self.device = device

    // Configure the device.
    try device.lockForConfiguration()
    device.activeVideoMaxFrameDuration = CMTimeMake(1, 30)
    device.unlockForConfiguration()

    let videoInput = try AVCaptureDeviceInput(device: device)

    // Capture raw images from the camera through the output object.
    let videoOutput = AVCaptureVideoDataOutput()
    videoOutput.setSampleBufferDelegate(self, queue: queue)
    videoOutput.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA)
    ]


    // Create a new capture session.
    captureSession.sessionPreset = AVCaptureSessionPreset640x480;
    captureSession.addInput(videoInput)
    captureSession.addOutput(videoOutput)
  }

  /**
   Called when a frame is available. Executed on the queue.

   The camera records at 640x480, but the image is cropped to 640x360
   in order to maintain the 16:9 aspect ratio of the iPhone screen.
   */
  func captureOutput(
      captureOutput: AVCaptureOutput!,
      didOutputSampleBuffer sampleBuffer: CMSampleBuffer!,
      fromConnection connection: AVCaptureConnection!)
  {
    guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return
    }
    

    CVPixelBufferLockBaseAddress(imageBuffer, 0)

    let addr = CVPixelBufferGetBaseAddress(imageBuffer)

    let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
    let width = CVPixelBufferGetWidth(imageBuffer)
    let height = CVPixelBufferGetHeight(imageBuffer)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGBitmapContextCreate(
        addr + 60 * bytesPerRow,
        width,
        height - 120,
        8,
        bytesPerRow,
        colorSpace,
        CGImageAlphaInfo.PremultipliedFirst.rawValue |
        CGBitmapInfo.ByteOrder32Little.rawValue
    )

    let quartzImage = CGBitmapContextCreateImage(context)
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);

    guard let image = quartzImage else {
      return
    }
  
    delegate?.onCameraFrame(UIImage(CGImage: image))
  }

  /**
   Starts recording frames.
   */
  func start() {
    captureSession.startRunning()
  }

  /**
   Stops recording frames.
   */
  func stop() {
    captureSession.stopRunning()
  }
}
