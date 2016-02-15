// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import CoreLocation
import UIKit


/**
 List of exposure times to capture.
 */
let kExposures = [
  CMTimeMake(1, 1000),
  CMTimeMake(1, 250),
  CMTimeMake(1, 100),
  CMTimeMake(1, 50),
  CMTimeMake(1, 10),
]


/**
 Controller responsible for HDR panoramic reconstruction.
 */
class AREnvironmentCaptureController
    : UIViewController
    , CLLocationManagerDelegate
    , ARHDRCameraDelegate
{
  // Set of exposure times to capture.
  
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
  private var builder: AREnvironmentBuilder!

  // Width of the environment map.
  private let kWidth = 2048

  // Height of the environment map.
  private let kHeight = 1024

  // Camera parameters.
  private var params: ARParameters!

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
        action: Selector("onSave")
    )

    // Create the environment renderer.
    renderer = try! AREnvironmentViewRenderer(view: view, width: kWidth, height: kHeight)
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
        f: params.f
    )
    builder = AREnvironmentBuilder(
        width: kWidth,
        height: kHeight
    )
    camera?.start()
    
    // Timer to run the rendering/update loop.
    timer = QuartzCore.CADisplayLink(target: self, selector: Selector("onFrame"))
    timer.addToRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
  }

  /**
   Called before the view is going to disappear.
   */
  override func viewWillDisappear(animated: Bool) {
    super.viewWillDisappear(animated)

    camera?.stop()
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
    { (UIAlertAction) in
      // Create a uniquely named folder in the environment directory.
      let directory = AREnvironment.getEnvironmentsDirectoryURL()

      // Extract the name.
      var name : String = "Environment"
      if let text = alert.textFields?.first?.text {
        if !text.isEmpty {
          name = text
        }
      }

      // Create an environment object and save it.
      let env = AREnvironment(
          path: directory.URLByAppendingPathComponent(NSUUID().UUIDString),
          name: name,
          location: self.location
      )
      env.save()

      // Set environment as current.
      NSUserDefaults().setObject(env.path.path!, forKey: "environment")

      // Go back to the previous controller.
      self.navigationController?.popViewControllerAnimated(true)
    })

    alert.addAction(UIAlertAction(
        title: "Cancel",
        style: .Cancel,
        handler: nil
    ))

    presentViewController(alert, animated: true, completion: nil)
  }

  //var count = 0
  /**
   Processes a frame from the device's camera.
   */
  func onCameraFrame(frame: [(CMTime, CMAttitude, UIImage)]) {
    let display = frame.last!

    /*
    let dir = NSFileManager.defaultManager().URLsForDirectory(
        .DocumentDirectory,
        inDomains: .UserDomainMask
    )[0].URLByAppendingPathComponent("Temp").URLByAppendingPathComponent("\(count)")
    count += 1

    try! NSFileManager.defaultManager().createDirectoryAtURL(
        dir,
        withIntermediateDirectories: true,
        attributes: nil
    )
    
    for var i in 0...frame.count - 1 {
      let att = frame[i].1
      let path = dir.URLByAppendingPathComponent("img_\(i)_\(att.pitch)_\(att.yaw)_\(att.roll).png")
      UIImagePNGRepresentation(frame[i].2)!.writeToFile(path.path!, atomically: true)
    }
    */

    builder.update(display.2, pose: ARPose(
        params: params,
        rx: -Float(display.1.pitch),
        ry:  Float(display.1.roll),
        rz: -Float(display.1.yaw),
        tx: 0.0,
        ty: 0.0,
        tz: 0.0
    ))
  }

  /**
   Called when attitude is refreshed. Renders feedback to the user.
   */
  func onFrame() {
    guard let attitude = motionManager.deviceMotion?.attitude else {
      return
    }

    if let preview = builder.getPreview() {
      renderer.update(preview)
    }

    renderer.updatePose(ARPose(
        projMat: float4x4(
            aspect: Float(view.frame.size.width / view.frame.size.height),
            fov: 45.0,
            n: 0.1,
            f: 100.0
        ),
        rx: -Float(attitude.pitch),
        ry:  Float(attitude.roll),
        rz: -Float(attitude.yaw),
        tx: 0.0,
        ty: 0.0,
        tz: 0.0
    ))
    renderer.renderFrame()
  }
}
