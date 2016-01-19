// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import UIKit

/**
 * Class responsible for displaying the main scene.
 */
@objc class ARSceneViewController : UIViewController {
  var params: ARParameters?
  var environment: AREnvironment?
  var timer: NSTimer?

  override func viewDidLoad() {
    super.viewDidLoad()
  }

  /**
   Called when the view is about to be loaded.
   */
  override func viewDidAppear(animated: Bool) {
    super.viewDidAppear(animated)

    // Set the title of the view.
    title = "MobileAR"

    // Hide both the navigation bar and the toolbar.
    if let nav = navigationController {
      nav.setToolbarHidden(true, animated: true)
      nav.setNavigationBarHidden(true, animated: true)

      let space = UIBarButtonItem(
          barButtonSystemItem: .FlexibleSpace,
          target: nil,
          action: nil
      )
      let btnCalibrate = UIBarButtonItem(
          barButtonSystemItem: .Camera,
          target: self,
          action: Selector("onCalibrate")
      )
      let btnBrowse = UIBarButtonItem(
          barButtonSystemItem: .Search,
          target: self,
          action: Selector("onSelect")
      )

      setToolbarItems([btnCalibrate, space, btnBrowse], animated: false)
    }

    // Fetch camera parameters & environment.
    //obtainCalibration()
    //obtainEnvironment()
  }

  /**
   Cancels all timers.
   */
  override func viewWillDisappear(animated: Bool) {
    timer?.invalidate()
  }

  /**
   Ensures that calibration parameters are available.

   If the parameters can be read from Documents/params.json, they are read.
   Otherwise, the user is promted to navigate to the calibration view.
   */
  private func obtainCalibration() {
    params = ARParameters.load()
    if params != nil {
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

    presentViewController(alert, animated: false) {}
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

      environment = try AREnvironment(path: url)
      if environment != nil {
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

    presentViewController(alert, animated: false) {}
  }

  /**
   Shows the toolbar whenever the user touches the screen.
   */
  override func touchesBegan(touches: Set<UITouch>, withEvent: UIEvent?) {
    navigationController?.setNavigationBarHidden(false, animated: true)
    navigationController?.setToolbarHidden(false, animated: true)
  }

  /**
   Hides the toolbar after the user lifts the figers from the screen.
   */
  override func touchesEnded(touches: Set<UITouch>, withEvent: UIEvent?) {
    timer = NSTimer.scheduledTimerWithTimeInterval(
        3,
        target: self,
        selector: Selector("onHide"),
        userInfo: nil,
        repeats: false
    )
  }

  func onCalibrate() {
    navigationController?.pushViewController(ARCalibrateController(), animated: true)
  }

  func onCapture() {
    navigationController?.pushViewController(AREnvironmentCaptureController(), animated: true)
  }

  func onSelect() {
    navigationController?.pushViewController(AREnvironmentListController(), animated: true)
  }

  func onHide() {
    navigationController?.setNavigationBarHidden(true, animated: true)
    navigationController?.setToolbarHidden(true, animated: true)
  }
}
