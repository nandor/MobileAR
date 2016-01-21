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

  /**
   Callend when the window is first created.
   */
  override func viewDidLoad() {
    super.viewDidLoad()

    title = "MobilerAR"
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
  }

  /**
   Called after the view was loaded.
   */
  override func viewDidAppear(animated: Bool) {
    // Fetch camera parameters & environment.
    obtainCalibration()
    obtainEnvironment()
  }

  /**
   Called when the view will disapper.
   */
  override func viewWillDisappear(animated: Bool) {
    super.viewWillDisappear(animated)
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

  func onCalibrate() {
    navigationController?.pushViewController(ARCalibrateController(), animated: true)
  }

  func onCapture() {
    navigationController?.pushViewController(AREnvironmentCaptureController(), animated: true)
  }

  func onSelect() {
    navigationController?.pushViewController(AREnvironmentListController(), animated: true)
  }
}
