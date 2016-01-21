// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import UIKit

class AREnvironmentViewController : UIViewController {
  var environment: AREnvironment!

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
   Called if the user wants to select the environment.
   */
  func onSelect() {
    NSUserDefaults().setObject(environment.path.path!, forKey: "environment")
    navigationController?.popToRootViewControllerAnimated(true)
  }
}
