// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import UIKit


/**
 View controller responsible with displaying a list of prepared environments.
 */
class AREnvironmentListController: UIViewController {

  /**
   Called before the view is displayed.
   */
  override func viewWillAppear(animated: Bool) {
    super.viewWillAppear(animated)

    // Set the title of the view.
    self.title = "Select"

    // Add a button to navigate to sphere capture.
    self.navigationItem.rightBarButtonItem = UIBarButtonItem(
        title: "Capture",
        style: .Plain,
        target: self,
        action: Selector("onCapture")
    )
  }

  /**
   Called after the view is displayed.
   */
  override func viewDidAppear(animated: Bool) {
    let path = (NSSearchPathForDirectoriesInDomains(
        .DocumentDirectory,
        .UserDomainMask,
        true
    )[0] as NSString).stringByAppendingPathComponent("Environments")

    NSLog(path)
    /*
    let fileManager = NSFileManager.defaultManager()
    let enumerator:NSDirectoryEnumerator = fileManager.enumeratorAtPath(folderPath)

    while let element = enumerator?.nextObject() as? String {
      if element.hasSuffix("ext") {
      }
    }*/
  }

  /**
   Called when the user clicks the Capture button.
   */
  func onCapture() {
    self.navigationController?.pushViewController(
        AREnvironmentCaptureController(),
        animated: true
    );
  }
}
