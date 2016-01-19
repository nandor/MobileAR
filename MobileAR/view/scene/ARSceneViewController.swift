// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import UIKit

/**
 * Class responsible for displaying the main scene.
 */
@objc class ARSceneViewController : UIViewController {
  private var hasCalibration : Bool = false;
  private var hasEnvironment : Bool = false;

  override func viewDidAppear(animated: Bool) {
    super.viewWillAppear(animated);

    self.title = "MobileAR";
    self.navigationController?.setNavigationBarHidden(true, animated: false);

    if (!hasCalibration) {
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
      self.presentViewController(alert, animated: false) {}
      self.navigationController?.setNavigationBarHidden(false, animated: false);
      return;
    }

    if (!hasEnvironment) {
      let alert = UIAlertController(
          title: "Missing Environment",
          message: "Please capture or select the light sources",
          preferredStyle: .Alert
      );
      alert.addAction(UIAlertAction(
          title: "Capture",
          style: .Default)
      { (UIAlertAction) in
        self.navigationController?.pushViewController(
            AREnvironmentCaptureController(),
            animated: true
        );
      });
      alert.addAction(UIAlertAction(
          title: "Select",
          style: .Default)
      { (UIAlertAction) in
        self.navigationController?.pushViewController(
            AREnvironmentListController(),
            animated: true
        );
      });
      self.presentViewController(alert, animated: false) {}
      self.navigationController?.setNavigationBarHidden(false, animated: false);
      return;
    }
  }
}
