// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import UIKit


/**
 Class that handles interactions between the system and the aplication.
 */
@UIApplicationMain
class ARAppDelegate: UIResponder, UIApplicationDelegate {
  /**
   Main window used throughout the app.
   */
  var window : UIWindow?

  /**
   Main navigation controller.
   */
  var navigation : UINavigationController?

  /**
   Called when the application finished loading and stuff is ready to be set up.
   */
  func application(
      application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?
  ) -> Bool
  {

    // Create the navigation controller.
    navigation = UINavigationController()
    navigation?.viewControllers = [ARSceneViewController()]

    // Create the window.
    window = UIWindow(frame: UIScreen.mainScreen().bounds)
    window?.backgroundColor = UIColor.blackColor()
    window?.rootViewController = navigation
    window?.makeKeyAndVisible()

    return true
  }
}
