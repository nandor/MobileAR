// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import CoreLocation
import UIKit
import QuartzCore

/**
 List of exposure times to capture.
 */
let kExposures = [
  CMTimeMake(1, 80),
  CMTimeMake(1, 40),
  CMTimeMake(1, 20),
]


/**
 Enumeration of capture errors.
 */
@objc enum ARCaptureError : Int, ErrorType {
  case Blurry
  case NotEnoughFeatures
  case NoPairwiseMatches
  case NoGlobalMatches
}


/**
 Controller responsible for HDR panoramic reconstruction.
 */
class AREnvironmentCaptureController
    : UIViewController
    , CLLocationManagerDelegate
    , ARHDRCameraDelegate
{
  // Location manager used to sort environments by distance.
  private var locationManager : CLLocationManager!
  // Motion manager used to capture attitude data.
  private var motionManager: CMMotionManager!
  // Camera wrapper.
  private var camera: ARHDRCamera!
  // Location provided by the location manager.
  private var location : CLLocation?
  // Timer used to redraw frames.
  private var timer: CADisplayLink!
  // Renderer used to display the sphere.
  private var renderer: AREnvironmentViewRenderer!
  // Class used to build the environment.
  private var builder: AREnvironmentBuilder?

  // Width of the environment map.
  private static let kWidth = 2048
  // Height of the environment map.
  private static let kHeight = 1024

  // Camera parameters.
  private var params: ARParameters!

  // Number of frames processed.
  private var count = 0

  // Message label.
  private var uiMessage: UILabel!
  // Spinner view.
  private var uiSpinner: UIActivityIndicatorView!

  /**
   Called when the view is first created.
   */
  override func viewDidLoad() {

    // Set up the location manager.
    locationManager = CLLocationManager()
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyBest
    locationManager.requestWhenInUseAuthorization()

    // Set up motionManager updates at a rate of 30Hz.
    motionManager = CMMotionManager()
    motionManager.deviceMotionUpdateInterval = 1 / 30.0
    motionManager.startDeviceMotionUpdatesUsingReferenceFrame(
        CMAttitudeReferenceFrame.XMagneticNorthZVertical
    )
  }

  /**
   Called before the view is displayed.
   */
  override func viewWillAppear(animated: Bool) {
    super.viewWillAppear(animated)

    // Load the camera parameters.
    params = try! ARParameters.loadFromFile()

    // Request a location update.
    locationManager.startUpdatingLocation()

    // Hide the toolbar and show the navigation bar.
    navigationController?.hidesBarsOnSwipe = false;
    navigationController?.setNavigationBarHidden(false, animated: animated)

    // Set the title of the view.
    title = "Capture"

    // Set up the save button.
    navigationItem.rightBarButtonItem = UIBarButtonItem(
        barButtonSystemItem: .Save,
        target: self,
        action: #selector(onSave)
    )

    // Create the environment renderer.
    renderer = try! AREnvironmentViewRenderer(
        view: view,
        width: AREnvironmentCaptureController.kWidth,
        height: AREnvironmentCaptureController.kHeight
    )

    // Initialize the UI.
    uiMessage = UILabel(frame: CGRect(
        x: (view.frame.width - 200) / 2,
        y: 100,
        width: 200,
        height: 20
    ))
    uiMessage.text = ""
    uiMessage.textAlignment = .Center
    uiMessage.textColor = UIColor.whiteColor()
    uiMessage.hidden = true
    view.addSubview(uiMessage)

    uiSpinner = UIActivityIndicatorView(frame: CGRect(
        x: (view.frame.width - 20) / 2,
        y: 150,
        width: 20,
        height: 20
    ))
    view.addSubview(uiSpinner)
  }

  /**
   Called after the view has appeared.
   */
  override func viewDidAppear(animated: Bool) {
    super.viewDidAppear(animated)

    // Create the camera. ISO is set very high in order to capture dark areas
    // with a short exposure duration. Exposure times are sorted shorted to
    // longest, such that the brightest image is taken last. The last image is
    // shown as feedback to the user, thus the time delay between recording that
    // image and showing it at its current pose using the gyro reading must be
    // minimized.
    camera = try! ARHDRCamera(
        delegate: self,
        motion: motionManager,
        exposures: kExposures,
        f: params.f,
        resolution: .Mid
    )
    camera.start()
    camera.expose(x: 0.5, y: 0.5) { (_) in
      self.builder = AREnvironmentBuilder(
        params: self.params,
        width: AREnvironmentCaptureController.kWidth,
        height: AREnvironmentCaptureController.kHeight
      )
    }

    // Timer to run the rendering/update loop.
    timer = CADisplayLink(target: self, selector: #selector(onFrame))
    timer.addToRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
  }

  /**
   Called before the view is going to disappear.
   */
  override func viewWillDisappear(animated: Bool) {
    super.viewWillDisappear(animated)

    camera.stop()
    timer.invalidate()
  }

  /**
   Called when new location information is available.
   */
  func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    location = manager.location
    manager.stopUpdatingLocation()
  }

  /**
   Called when the user wants to save the captured environment.

   Displays an alert with a text input in order to choose the name of the environment.
   */
  func onSave() {
    let alert = UIAlertController(
        title: "Save",
        message: "Save and use the environment.",
        preferredStyle: .Alert
    )

    alert.addTextFieldWithConfigurationHandler() {
      $0.placeholder = "Environment"
    }

    alert.addAction(UIAlertAction(
        title: "Save",
        style: .Default)
    { (_) in
      // Create a uniquely named folder in the environment directory.
      let directory = AREnvironment.getEnvironmentsDirectoryURL()

      // Extract the name.
      var name : String = "Environment"
      if let text = alert.textFields?.first?.text {
        if !text.isEmpty {
          name = text
        }
      }

      // Create the panorama.
      self.uiSpinner.startAnimating()
      self.builder?.composite() { message, images in
        self.uiMessage.text = message
        self.uiMessage.hidden = false

        if let images = images {
          // Save the environment to disk.
          self.saveEnvironment(
              name,
              path: directory.URLByAppendingPathComponent(NSUUID().UUIDString),
              images: images
          )

          // Clear the UI.
          self.builder = .None
          self.uiSpinner.stopAnimating()
          self.uiMessage.hidden = true
        }
      }
    })

    alert.addAction(UIAlertAction(
        title: "Cancel",
        style: .Cancel,
        handler: nil
    ))

    presentViewController(alert, animated: true, completion: nil)
  }

  /**
   Processes a frame from the device's camera.
   */
  func onCameraFrame(frame: [(UIImage, CMAttitude, CMTime)]) {

    // Convert the frames to a nicer format.
    let frames : [ARHDRFrame] = frame.sort() { return CMTimeCompare($0.2, $1.2) < 0 }.map() {
      return ARHDRFrame(
          frame: $0,
          pose: ARPose(
              params: params,
              rx: +Float($1.roll),
              ry: -Float($1.pitch),
              rz: -Float($1.yaw),
              tx: 0.0,
              ty: 0.0,
              tz: 0.0
          ),
          exposure: $2
      )
    }
    
    // Update the enviroment builder & bail out if the image does not
    // fit into the composited photo sphere.
    do {
      try builder?.update(frames)
    } catch {
      switch (ARCaptureError(rawValue: (error as NSError).code)!) {
        case .Blurry:            print("Blurry")
        case .NotEnoughFeatures: print("NotEnoughFeatures")
        case .NoPairwiseMatches: print("NoPairwiseMatches")
        case .NoGlobalMatches:   print("NoGlobalMatches")
      }
      return
    }
    
    // Queue the image for compositing.
    renderer.update(frames.last!.frame, pose: frames.last!.pose)
  }

  /**
   Called when attitude is refreshed. Renders feedback to the user.
   */
  func onFrame() {

    guard let attitude = motionManager.deviceMotion?.attitude else {
      return
    }

    renderer.updatePose(ARPose(
        projMat: float4x4(
            aspect: Float(view.frame.size.width / view.frame.size.height),
            fov: 45.0,
            n: 0.1,
            f: 100.0
        ),
        rx: Float(attitude.roll),
        ry: -Float(attitude.pitch),
        rz: -Float(attitude.yaw),
        tx: 0.0,
        ty: 0.0,
        tz: 0.0
    ))

    renderer.renderFrame()
  }

  /**
   Saves a panorama to disk.
   */
  func saveEnvironment(name: String, path: NSURL, images: [AREnvironmentMap]) {
    
    // Create an environment object and save it.
    let env = AREnvironment(
      path: path,
      name: name,
      location: location,
      images: images
    )
    try! env.save()

    // Set environment as current.
    NSUserDefaults().setObject(env.path.path!, forKey: "environment")

    // Show the environment.
    self.navigationController?.popViewControllerAnimated(true)
  }

  /**
   Saves a frame to disk.
   */
  func saveFrame(frame: [(UIImage, CMAttitude, CMTime)]) {

    let temp = NSFileManager.defaultManager().URLsForDirectory(
      .DocumentDirectory,
      inDomains: .UserDomainMask
    )[0].URLByAppendingPathComponent("Temp")

    let dir = temp.URLByAppendingPathComponent("\(count)")

    if count == 0 {
      try! NSFileManager.defaultManager().removeItemAtURL(temp)
    }
    try! NSFileManager.defaultManager().createDirectoryAtURL(
      dir,
      withIntermediateDirectories: true,
      attributes: nil
    )

    count += 1

    for i in 0...frame.count - 1 {
      let att = frame[i].1
      let path = dir.URLByAppendingPathComponent("img_\(i)_\(att.pitch)_\(att.yaw)_\(att.roll).png")
      UIImagePNGRepresentation(frame[i].0)!.writeToFile(path.path!, atomically: false)
    }
  }
}
