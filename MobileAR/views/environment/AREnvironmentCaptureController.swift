// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import CoreLocation
import UIKit

class AREnvironmentCaptureController : UIViewController, CLLocationManagerDelegate {

  // Location manager used to sort environments by distance.
  private var locationManager : CLLocationManager!

  // Location provided by the location manager.
  private var location : CLLocation?

  /**
   Called before the view is displayed.
   */
  override func viewWillAppear(animated: Bool) {
    super.viewWillAppear(animated)

    // Set up the location manager.
    locationManager = CLLocationManager()
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyBest
    locationManager.requestWhenInUseAuthorization()
    locationManager.startUpdatingLocation()

    // Hide the toolbar and show the navigation bar.
    navigationController?.hidesBarsOnSwipe = false;
    navigationController?.setNavigationBarHidden(false, animated: animated)

    // Set the title of the view.
    title = "Capture"

    // Set the background color to black.
    view.backgroundColor = UIColor.blackColor();

    // Set up the save button.
    navigationItem.rightBarButtonItem = UIBarButtonItem(
        barButtonSystemItem: .Save,
        target: self,
        action: Selector("onSave")
    )
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
}
