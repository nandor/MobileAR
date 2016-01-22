// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import UIKit
import CoreMotion
import QuartzCore


/**
 View responsible for displaying a captured spherical image.
 */
class AREnvironmentViewController : UIViewController {

  // Environment being displayed.
  var environment: AREnvironment!

  // Motion manager used to capture attitude data.
  var motion: CMMotionManager!

  // Timer used to redraw frames.
  var timer: CADisplayLink!

  // Renderer used to display the sphere.
  var renderer: ARRenderer!

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

    // Set up motion updates at a rate of 30Hz.
    motion = CMMotionManager()
    motion.deviceMotionUpdateInterval = 1 / 30.0
    motion.startDeviceMotionUpdatesUsingReferenceFrame(
        CMAttitudeReferenceFrame.XTrueNorthZVertical
    )

    // Initialize the renderer.
    renderer = try! ARRenderer(view: view)
  }

  /**
   Called before the view is displayed.
   */
  override func viewWillAppear(animated: Bool) {
    super.viewWillAppear(animated)

    // Sets the tile of the view.
    title = environment?.name ?? "Environment"

    // Hide the toolbar and show the navigation bar.
    navigationController?.hidesBarsOnSwipe = false;
    navigationController?.setNavigationBarHidden(false, animated: animated)
    navigationController?.setToolbarHidden(true, animated: animated)

    // Back background colour to avoid ugly animations.
    view.backgroundColor = UIColor.blackColor();

    // Add a button to select the environment.
    navigationItem.rightBarButtonItem = UIBarButtonItem(
        title: "Select",
        style: .Plain,
        target: self,
        action: Selector("onSelect")
    )
  }

  /**
   Called after the view has appeared.
   */
  override func viewDidAppear(animated: Bool) {
    super.viewDidAppear(animated)

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
    renderer.render()
  }
}
