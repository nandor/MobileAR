// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import Foundation


/**
 Protocol to handle a set of frames.
 */
protocol ARHDRCameraDelegate {
  func onCameraFrame(frame: [(CMTime, UIImage)])
}

/**
 Camera that outputs sets of images taken at multiple exposure durations.
 
 All the camera paramters (white balance, ISO, focus) are locked and exposure
 duration is varied in order to obtain a set of images suitable to recover
 the HDR response function from.
 */
class ARHDRCamera : ARCamera, ARCameraDelegate {
  
  // List of exposure durations.
  private let exposures: [CMTime]
  
  // Camera delegate that receives the frames.
  private let hdrDelegate: ARHDRCameraDelegate?
  
  // Fixed ISO value, controlling sensor gain.
  private let ISO: Float
  
  // Current exposure index.
  private var exposure: Int = 0
  
  // Buffer of saved frames.
  private var buffer: [(CMTime, UIImage)] = []
  
  // True if device is being configured.
  private var isBeingConfigured = false
  
  // True if exposure was configured and frame can be recorded.
  private var canTakeFrame = false
  
  /**
   Initializes the camera.
   */
  init(delegate: ARHDRCameraDelegate?, exposures: [CMTime], ISO: Float) throws {
    
    // Save config.
    self.hdrDelegate = delegate
    self.exposures = exposures
    self.ISO = ISO
    
    // Initialize superclass, registering this class as a handler.
    try super.init(delegate: nil)
    super.delegate = self
  }
  
  
  /**
   Called when a frame is ready.
   */
  func onCameraFrame(frame: UIImage) {
    
    // Skip if config is being tweaked.
    if (isBeingConfigured) {
      return
    }
    
    if (canTakeFrame) {
      
      // If exposure is right, add image to buffer.
      buffer.append((exposures[exposure], frame))
      exposure += 1
      
      // If buffer full, start new frame.
      if (exposure >= exposures.count) {
        hdrDelegate?.onCameraFrame(buffer)
        buffer.removeAll()
        exposure = 0
      }
      
      canTakeFrame = false
    }
    
    // If the exposure duration is wrong, reset it. Stop the camera until the
    // new value is adopted by the device. Also ensure that automatic white
    // balance adjustment is disabled and ISO is fixed.
    do {
      // Stop the device & lock for config.
      try device.lockForConfiguration()
      
      device.whiteBalanceMode = .Locked
      
      // Change exposure level.
      isBeingConfigured = true
      device.setExposureModeCustomWithDuration(
          exposures[exposure],
          ISO: ISO)
      { (CMTime time) in
        self.device.unlockForConfiguration()
        self.isBeingConfigured = false
        self.canTakeFrame = true
      }
    } catch {
    }
  }
}