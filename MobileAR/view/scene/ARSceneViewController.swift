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
   Called when the view is about to be loaded.
   */
  override func viewDidAppear(animated: Bool) {
    super.viewDidAppear(animated)

    // Set the title of the view.
    title = "MobileAR"

    // Hide the navigation bar in this view.
    navigationController?.setNavigationBarHidden(true, animated: false)

    // Fetch camera parameters & environment.
    obtainCalibration()
    obtainEnvironment()
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
    { (UIAlertAction) in
      self.navigationController?.pushViewController(
      ARCalibrateController(),
          animated: true
      );
    });

    presentViewController(alert, animated: false) {}
    navigationController?.setNavigationBarHidden(false, animated: false)
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
        style: .Default) {
      (UIAlertAction) in
      self.navigationController?.pushViewController(
      AREnvironmentCaptureController(),
          animated: true
      );
    });

    alert.addAction(UIAlertAction(
    title: "Select",
        style: .Default) {
      (UIAlertAction) in
      self.navigationController?.pushViewController(
      AREnvironmentListController(),
          animated: true
      );
    });

    self.presentViewController(alert, animated: false) {}
    self.navigationController?.setNavigationBarHidden(false, animated: false);
  }
}
