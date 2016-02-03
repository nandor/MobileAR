// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import CoreLocation
import UIKit

class AREnvironmentCaptureController
    : UIViewController
    , CLLocationManagerDelegate
    , ARCameraDelegate
{

  // Location manager used to sort environments by distance.
  private var locationManager : CLLocationManager!

  // Motion manager used to capture attitude data.
  private var motionManager: CMMotionManager!

  // Camera wrapper.
  private var camera: ARCamera!

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
        CMAttitudeReferenceFrame.XTrueNorthZVertical
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

    // Create the environment builder.
    builder = AREnvironmentBuilder(width: kWidth, height: kHeight)
    renderer = try! AREnvironmentViewRenderer(view: view, width: kWidth, height: kHeight)

    // Timer to run the rendering/update loop.
    timer = QuartzCore.CADisplayLink(target: self, selector: Selector("onFrame"))
    timer.addToRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
  }

  /**
   Called after the view has appeared.
   */
  override func viewDidAppear(animated: Bool) {
    super.viewDidAppear(animated)

    camera = try! ARCamera(delegate: self)
    camera?.start()
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

  /**
   Processes a frame from the device's camera.
   */
  func onCameraFrame(frame: UIImage) {
    guard let attitude = motionManager.deviceMotion?.attitude else {
      return
    }
    builder.update(frame, pose: ARPose(
        params: params,
        rx: -Float(attitude.pitch),
        ry: -Float(attitude.yaw),
        rz: Float(attitude.roll),
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
        params: params,
        rx: -Float(attitude.pitch),
        ry: -Float(attitude.yaw),
        rz: Float(attitude.roll),
        tx: 0.0,
        ty: 0.0,
        tz: 0.0
    ))
    renderer.renderFrame()
  }
}
