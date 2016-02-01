// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import UIKit

/**
 Object being rendered - references a model and a pose.
 */
class AREntity {

}

/**
 Class responsible for displaying the main scene.
 */
@objc class ARSceneViewController : UIViewController, ARCameraDelegate {
  // Camera parameters.
  internal var params: ARParameters?

  // Environment being used.
  internal var environment: AREnvironment?

  // Entities being rendered.
  internal var entities: [AREntity] = []

  // Camera wrapper.
  internal var camera: ARCamera!

  // Pose tracker.
  internal var tracker: ARSceneTracker!

  // Renderer used to draw the scene.
  internal var renderer: ARSceneRenderer!

  // Motion manager used to capture attitude data.
  internal var motionManager: CMMotionManager!

  // Timer used to redraw frames.
  private var timer: CADisplayLink!
  
  /**
   Callend when the window is first created.
   */
  override func viewDidLoad() {
    super.viewDidLoad()
  }

  /**
   Called when the view is about to be loaded.
   */
  override func viewWillAppear(animated: Bool) {
    super.viewWillAppear(animated)

    // Display the toolbar and navigation bar, but allow them to be hidden.
    navigationController?.setNavigationBarHidden(false, animated: animated)
    navigationController?.hidesBarsOnSwipe = true;

    // Set up the toolbar items.
    navigationItem.rightBarButtonItem = UIBarButtonItem(
        barButtonSystemItem: .Camera,
        target: self,
        action: Selector("onCalibrate")
    )
    navigationItem.leftBarButtonItem = UIBarButtonItem(
        barButtonSystemItem: .Search,
        target: self,
        action: Selector("onSelect")
    )

    // Reset the title.
    title = "MobilerAR"
  }

  /**
   Called after the view was loaded.
   */
  override func viewDidAppear(animated: Bool) {
    // Obtain permission to use the camera. Fetch camera params & environment.
    obtainCamera()
    obtainCalibration()
    obtainEnvironment()

    if camera == nil || params == nil || environment == nil {
      return
    }

    // Initialize components.
    tracker = ARSceneTracker(parameters: params)
    renderer = try! ARSceneRenderer(view: view)
    motionManager = CMMotionManager()
    motionManager.deviceMotionUpdateInterval = 1 / 30.0
    motionManager.startDeviceMotionUpdatesUsingReferenceFrame(
        CMAttitudeReferenceFrame.XTrueNorthZVertical
    )

    // Timer to run the rendering/update loop.
    timer = QuartzCore.CADisplayLink(target: self, selector: Selector("onFrame"))
    timer.addToRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)

    // Start the camera.
    camera.start()
  }

  /**
   Called when the view will disapper.
   */
  override func viewWillDisappear(animated: Bool) {
    super.viewWillDisappear(animated)
    timer.invalidate()
    camera.stop()
  }

  /**
   Ensures that calibration parameters are available.

   If the parameters can be read from Documents/params.json, they are read.
   Otherwise, the user is promted to navigate to the calibration view.
   */
  private func obtainCalibration() {
    if let calibrationParams = try? ARParameters.loadFromFile() {
      params = calibrationParams
      return
    }

    let alert = UIAlertController(
        title: "Missing Calibration",
        message: "Please calibrate the camera",
        preferredStyle: .Alert
    );

    alert.addAction(UIAlertAction(
        title: "Calibrate",
        style: .Default)
    { (UIAlertAction) in self.onCalibrate() })

    presentViewController(alert, animated: true, completion: nil)
  }

  /**
   Ensures that an environment is selected.
   */
  private func obtainEnvironment() {
    if params == nil {
      return
    }

    if let path = NSUserDefaults().stringForKey("environment") {
      let url = NSURL.fileURLWithPath(path, isDirectory: true)

      environment = try? AREnvironment(path: url)
      if environment != nil {
        title = "MobileAR - \(environment!.name)"
        return
      }
    }

    let alert = UIAlertController(
        title: "Missing Environment",
        message: "Please capture or select the light sources",
        preferredStyle: .Alert
    );

    alert.addAction(UIAlertAction(
        title: "Capture",
        style: .Default)
    { (UIAlertAction) in self.onCapture() })

    alert.addAction(UIAlertAction(
        title: "Select",
        style: .Default)
    { (UIAlertAction) in self.onSelect() })

    presentViewController(alert, animated: true, completion: nil)
  }

  /**
   Create the camera. If the user does not provide permission, ask for it.
   */
  func obtainCamera() {

    if let cam = try? ARCamera(delegate: self) {
      camera = cam
      return
    }

    let alert = UIAlertController(
        title: "Camera Permission",
        message: "Please enable the camera in Settings > MobileAR",
        preferredStyle: .Alert
    )

    alert.addAction(UIAlertAction(
        title: "Okay",
        style: .Default)
    { (UIAlertAction) in self.obtainCamera() })

    alert.addAction(UIAlertAction(
        title: "Back",
        style: .Cancel)
    { (UIAlertAction) in self.navigationController?.popToRootViewControllerAnimated(true) })

    presentViewController(alert, animated: true, completion: nil)
  }

  // Handle button taps.
  func onCalibrate() {
    navigationController?.pushViewController(ARCalibrateController(), animated: true)
  }
  func onCapture() {
    navigationController?.pushViewController(AREnvironmentCaptureController(), animated: true)
  }
  func onSelect() {
    navigationController?.pushViewController(AREnvironmentListController(), animated: true)
  }

  /**
   Processes a frame from the device's camera.
   */
  func onCameraFrame(frame: UIImage) {
    tracker.trackFrame(frame)
    self.renderer.updateFrame(frame)
  }
  
  var angle: Float = 0.0
  /**
   Updates the tracker & renders a frame.
   */
  func onFrame() {

    guard let attitude = motionManager.deviceMotion?.attitude else {
      return
    }
    guard let acceleration = motionManager.deviceMotion?.userAcceleration else {
      return
    }

    // Update the tracker.
    tracker.trackSensor(attitude, acceleration: acceleration)
    
    // Update the extrinsic parameters in the renderer.
    renderer.updatePose(
        rx: angle,
        ry: 0.0,
        rz: 0.0,
        tx: 0.0,
        ty: -2.0,
        tz: -7.0
    )
    
    angle += 0.01
    
    //renderer.updatePose(tracker.getPose())
    
    self.renderer.renderFrame()
  }
}
