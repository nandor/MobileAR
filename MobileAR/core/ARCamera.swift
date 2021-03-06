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

enum ARCameraResolution {
  case Low  // 640x360
  case Mid  // 1280x720
  case High // 1920x1080
}


/**
 Wrapper around AVFoundation camera.
 */
class ARCamera : NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

  // Dispatch queue to execute camera code on.
  private let cameraQueue = dispatch_queue_create(
      "uk.ac.ic.MobileAR.ARCameraFetchQueue",
      DISPATCH_QUEUE_SERIAL
  )
  // Dispatch queue to execute notification blocks on.
  private let queueCalibrate = dispatch_queue_create(
    "uk.ac.ic.MobileAR.ARCameraWaitQueue",
    DISPATCH_QUEUE_SERIAL
  )
  
  // Semaphore to signal auto-focus.
  private let semaFocus = dispatch_semaphore_create(0)
  // Semaphore to signal auto-exposure.
  private let semaExposure = dispatch_semaphore_create(0)
  
  
  // Capture session for start/stop.
  internal let captureSession = AVCaptureSession()
  // User-specified callback.
  internal var delegate: ARCameraDelegate?
  // Camera device.
  internal var device: AVCaptureDevice!
  // Indicates that the camera is begin configured.
  internal var configuring: Bool = false

  // Resolution of the image.
  internal let resolution: ARCameraResolution
  
  
  /**
   Iniitalizes the camera wrapper.
   */
  init(delegate: ARCameraDelegate?, f: Float, resolution: ARCameraResolution) throws {
    self.delegate = delegate
    self.resolution = resolution

    super.init()

    // Try to get access to the default device.
    guard let device = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo) else {
      throw ARCameraError.NotAuthorized
    }
    self.device = device

    // Configure the device.
    try! device.lockForConfiguration()
    device.whiteBalanceMode = .ContinuousAutoWhiteBalance
    device.exposureMode = .ContinuousAutoExposure
    device.activeVideoMaxFrameDuration = CMTimeMake(1, 30)
    device.setFocusModeLockedWithLensPosition(f, completionHandler: nil)
    device.unlockForConfiguration()

    let videoInput = try AVCaptureDeviceInput(device: device)

    // Capture raw images from the camera through the output object.
    let videoOutput = AVCaptureVideoDataOutput()
    videoOutput.setSampleBufferDelegate(self, queue: cameraQueue)
    videoOutput.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA)
    ]

    // Create a new capture session.
    switch resolution {
      case .Low: captureSession.sessionPreset = AVCaptureSessionPreset640x480;
      case .Mid: captureSession.sessionPreset = AVCaptureSessionPreset1280x720;
      case .High: captureSession.sessionPreset = AVCaptureSessionPreset1920x1080;
    }
    captureSession.addInput(videoInput)
    captureSession.addOutput(videoOutput)

    // Watch exposure & focus modes.
    for key in ["exposureMode", "focusMode"] {
      device.addObserver(
          self,
          forKeyPath: key,
          options: [
              NSKeyValueObservingOptions.New,
              NSKeyValueObservingOptions.Old
          ],
          context: nil
      )
    }
  }

  deinit {
    for key in ["exposureMode", "focusMode"] {
      device.removeObserver(self, forKeyPath: key)
    }
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

    var crop = 0
    switch resolution {
      case .Low: crop = 60
      case .Mid: crop = 0
      case .High: crop = 0
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGBitmapContextCreate(
        addr + crop * bytesPerRow,
        width,
        height - crop * 2,
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
   Changes the focus point of the camera.

   Adjusts the point of interest for both focus and exposure.
   */
  func focus(x x: Float, y: Float, completionHandler: (Float) -> ()) {
    let point = CGPoint(x: CGFloat(x), y: CGFloat(y))
    let scheduled = CFAbsoluteTimeGetCurrent()
    
    configuring = true
    dispatch_async(queueCalibrate) {
      // Bail out if it took longer than half a second.
      guard CFAbsoluteTimeGetCurrent() - scheduled < 0.5 else {
        return
      }
      
      // Set the focal distance & exposure to automatic.
      try! self.device.lockForConfiguration()
      self.device.focusPointOfInterest = point
      self.device.focusMode = .AutoFocus
      self.device.exposurePointOfInterest = point
      self.device.exposureMode = .AutoExpose
      self.device.unlockForConfiguration()
      
      // Block until both changes are reported.
      dispatch_semaphore_wait(self.semaExposure, DISPATCH_TIME_FOREVER);
      dispatch_semaphore_wait(self.semaFocus, DISPATCH_TIME_FOREVER);
      
      // Execute the callback.
      completionHandler(self.device.lensPosition)
      self.configuring = false
    }
  }

  /**
   Starts auto-exposure, focusing on a single point.
   */
  func expose(x x: Float, y: Float, completionHandler: (CMTime) -> ()) {
    let point = CGPoint(x: CGFloat(x), y: CGFloat(y))
    let scheduled = CFAbsoluteTimeGetCurrent()
    
    configuring = true
    dispatch_async(queueCalibrate) {
      // Bail out if it took longer than half a second.
      guard CFAbsoluteTimeGetCurrent() - scheduled < 0.5 else {
        return
      }
      
      // Obtain access to camera.
      try! self.device.lockForConfiguration()
      
      // Start auto-exposure and wait for completion.
      self.device.exposurePointOfInterest = point
      self.device.exposureMode = .AutoExpose
      dispatch_semaphore_wait(self.semaExposure, DISPATCH_TIME_FOREVER)
      self.device.whiteBalanceMode = .Locked
      
      // Release access to camera.
      self.device.unlockForConfiguration()
      
      // Execute the callback.
      completionHandler(self.device.exposureDuration)
      self.configuring = false
    }
  }

  /**
   Observes changes to focusMode and exposureMode.
   */
  override func observeValueForKeyPath(
      keyPath: String?,
      ofObject: AnyObject?,
      change: [String : AnyObject]?,
      context: UnsafeMutablePointer<Void>)
  {
    guard let oldVal = change?["old"] as? Int else { return }
    guard let newVal = change?["new"] as? Int else { return }

    switch keyPath {
    case .Some("exposureMode"):
      let old = AVCaptureExposureMode(rawValue: oldVal)
      let new = AVCaptureExposureMode(rawValue: newVal)

      if old == .AutoExpose && new == .Locked {
        dispatch_semaphore_signal(semaExposure)
      }
      
    case .Some("focusMode"):
      let old = AVCaptureFocusMode(rawValue: oldVal)
      let new = AVCaptureFocusMode(rawValue: newVal)
  
      if old == .AutoFocus && new == .Locked {
        dispatch_semaphore_signal(semaFocus)
      }
      
    default:
      return
    }
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
