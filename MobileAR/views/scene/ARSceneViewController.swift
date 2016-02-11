// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import UIKit


/**
 Extension to provide access to acceleration in the reference frame.
 */
extension CMDeviceMotion {

  var rotatedAcceleration: CMAcceleration {
    get {
      let a = self.userAcceleration
      let r = self.attitude.rotationMatrix

      let R = double3x3([
          double3(r.m11, r.m21, r.m31),
          double3(r.m12, r.m22, r.m32),
          double3(r.m13, r.m23, r.m33)
      ])
      let ar = R.inverse * double3(a.x, a.y, a.z)

      return CMAcceleration(x: ar.x, y: ar.y, z: ar.z)
    }
  }
}


/**
 Class responsible for displaying the main scene.
 */
@objc class ARSceneViewController : UIViewController, ARCameraDelegate {
  // Camera parameters.
  private var params: ARParameters?

  // Environment being used.
  private var environment: AREnvironment?

  // Camera wrapper.
  private var camera: ARCamera!

  // Pose tracker.
  private var tracker: ARPoseTracker!

  // Renderer used to draw the scene.
  private var renderer: ARSceneRenderer!

  // Motion manager used to capture attitude data.
  private var motionManager: CMMotionManager!

  // Timer used to redraw frames.
  private var timer: CADisplayLink!

  struct ARPlane {
    let n: float3
    let o: float3
  }
  private let plane = ARPlane(n: float3(0, 0, -1), o: float3(0, 0, 0))

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


    // Start tracking orientation.
    motionManager = CMMotionManager()
    motionManager.deviceMotionUpdateInterval = 1 / 30.0
    motionManager.startDeviceMotionUpdatesUsingReferenceFrame(
        CMAttitudeReferenceFrame.XMagneticNorthZVertical
    )

    // Initialize the scene tracker.
    tracker = ARMarkerPoseTracker(parameters: params)
    //tracker = ARDemoPoseTracker(aspect: Float(view.frame.width / view.frame.height));

    // Initialize the renderer.
    renderer = try! ARSceneRenderer(view: view, environment: environment!)

    renderer.objects.append(ARObject(
      mesh: "cube",
      model: float4x4(t: float3(0, 0, 0))
    ))


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

  /**
   Updates the tracker & renders a frame.
   */
  func onFrame() {

    guard let attitude = motionManager.deviceMotion?.attitude else {
      return
    }
    guard let acceleration = motionManager.deviceMotion?.rotatedAcceleration else {
      return
    }

    // Update the tracker.
    tracker.trackSensor(attitude, acceleration: acceleration)
    renderer.updatePose(tracker.getPose())
    self.renderer.renderFrame()
  }

  /**
   Called when the user taps on the screen and an object is to be added.
   */
  override func touchesEnded(touches: Set<UITouch>, withEvent: UIEvent?) {
    let pose = tracker.getPose()

    for touch in touches {
      // Find the screen space coordinate of the touch.
      let location = touch.locationInView(view)
      let x = Float(location.x / view.frame.width * 2.0 - 1.0)
      let y = Float(1.0 - location.y / view.frame.height * 2.0)

      // Unproject to get intersection on near & far planes.
      let p0 = pose.unproject(float3(x, y, -1.0))
      let p1 = pose.unproject(float3(x, y,  1.0))
      let dir = normalize(p1 - p0)

      // Intersect the ray with the plane.
      let d = -(dot(p0, plane.n) - dot(plane.o, plane.n)) / dot(dir, plane.n)
      if d <= 0.0 {
        continue
      }

      // Add an object at the intersection point.
      renderer.objects.append(ARObject(
          mesh: "cube",
          model: float4x4(t: p0 + d * dir)
      ))
    }
  }
}
