// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import UIKit

class AREnvironmentViewController : UIViewController {

  override func viewWillAppear(animated: Bool) {
    super.viewWillAppear(animated)

    // Hide the toolbar and show the navigation bar.
    navigationController?.hidesBarsOnSwipe = false;
    navigationController?.setNavigationBarHidden(false, animated: animated)
    navigationController?.setToolbarHidden(true, animated: animated)

    // Back background colour to avoid ugly animations.
    view.backgroundColor = UIColor.blackColor();

    // Set the title of the view.
    title = "Environment"

    // Add a button to select the environment.
    navigationItem.rightBarButtonItem = UIBarButtonItem(
        title: "Select",
        style: .Plain,
        target: self,
        action: Selector("onSelect")
    )
  }

  func onSelect() {
    navigationController?.popToRootViewControllerAnimated(true)
  }
}
