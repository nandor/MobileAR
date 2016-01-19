// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "ARAppDelegate.h"
#import "MobileAR-Swift.h"


@implementation ARAppDelegate
{
  UIWindow *window;
  UINavigationController *navigation;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  // Create the navigation controller.
  navigation = [[UINavigationController alloc] initWithRootViewController:[[ARSceneViewController alloc] init]];

  // Create the window.
  window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
  window.backgroundColor = [UIColor blackColor];
  window.rootViewController = navigation;
  [window makeKeyAndVisible];
  return YES;
}

@end
