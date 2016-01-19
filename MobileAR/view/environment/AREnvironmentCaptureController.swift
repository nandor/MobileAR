// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import UIKit

class AREnvironmentCaptureController : UIViewController {

  /**
   Called before the view is displayed.
   */
  override func viewWillAppear(animated: Bool) {
    super.viewWillAppear(animated)

    // Hide the toolbar and show the navbar.
    if let nav = navigationController {
      nav.setToolbarHidden(true, animated: animated)
      nav.setNavigationBarHidden(false, animated: animated)
    }

    // Set the title of the view.
    title = "Capture"

    view.backgroundColor = UIColor.blackColor();
  }
}
