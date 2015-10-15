// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "ARAppDelegate.h"
#import "ARMainViewController.h"

@implementation ARAppDelegate
{
  
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  _window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
  _window.backgroundColor = [UIColor blueColor];
  [_window setRootViewController:[[ARMainViewController alloc] init]];
  [_window makeKeyAndVisible];
  return YES;
}

- (void)applicationWillTerminate:(UIApplication *)application
{
}

@end
