// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import Darwin
import UIKit
import CoreMotion
import QuartzCore


/**
 View responsible for displaying a captured spherical image.
 */
class AREnvironmentViewController : UIViewController {

  // Environment being displayed.
  private var environment: AREnvironment!

  // Motion manager used to capture attitude data.
  private var motionManager: CMMotionManager!

  // Timer used to redraw frames.
  private var timer: CADisplayLink!

  // Renderer used to display the sphere.
  private var renderer: AREnvironmentViewRenderer!

  /**
   Initializes the controller with an environment.
   */
  init(environment: AREnvironment) {
    self.environment = environment
    super.init(nibName: nil, bundle: nil)
  }

  /**
   Initializer for loading from storyboard.
   */
  required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
  }

  /**
   Called when the view is first loaded.
   */
  override func viewDidLoad() {
    super.viewDidLoad()

    // Set up motionManager updates at a rate of 30Hz.
    motionManager = CMMotionManager()
    motionManager.deviceMotionUpdateInterval = 1 / 30.0
    motionManager.startDeviceMotionUpdatesUsingReferenceFrame(
        CMAttitudeReferenceFrame.XTrueNorthZVertical
    )

    // Initialize the renderer.
    renderer = try! AREnvironmentViewRenderer(view: view, environment: environment)
  }

  /**
   Called before the view is displayed.
   */
  override func viewWillAppear(animated: Bool) {
    super.viewWillAppear(animated)

    // Sets the tile of the view.
    title = environment.name ?? "Environment"

    // Hide the toolbar and show the navigation bar.
    navigationController?.hidesBarsOnSwipe = false;
    navigationController?.setNavigationBarHidden(false, animated: animated)
    navigationController?.setToolbarHidden(true, animated: animated)

    // Back background colour to avoid ugly animations.
    view.backgroundColor = UIColor.blackColor()

    // Add a button to select the environment.
    navigationItem.rightBarButtonItem = UIBarButtonItem(
        title: "Select",
        style: .Plain,
        target: self,
        action: Selector("onSelect")
    )

    // Timer to run the rendering/update loop.
    timer = QuartzCore.CADisplayLink(target: self, selector: Selector("onFrame"))
    timer.addToRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
  }

  /**
   Called before the view is going to disappear.
   */
  override func viewWillDisappear(animated: Bool) {
    super.viewWillDisappear(animated)

    timer.invalidate()
  }

  /**
   Called if the user wants to select the environment.
   */
  func onSelect() {
    NSUserDefaults().setObject(environment.path.path!, forKey: "environment")
    navigationController?.popToRootViewControllerAnimated(true)
  }
  
  /**
   Called when attitude is refreshed.
   */
  func onFrame() {
    guard let attitude = motionManager.deviceMotion?.attitude else {
      return
    }

    renderer.updatePose(ARPose(
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
