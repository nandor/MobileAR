// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import UIKit

class AREnvironmentViewController : UIViewController {

  override func viewWillAppear(animated: Bool) {
    super.viewWillAppear(animated)

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
