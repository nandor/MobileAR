// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <UIKit/UIKit.h>

@interface ARSceneViewController : UIViewController

/**
 * Initializes the store by providing its path.
 */
- (instancetype) initWithPath:(NSURL*) path;

/**
 * Checks if the parameters have been loaded.
 */
- (BOOL) loaded;

/**
 * Saves the calibration parameters to the file.
 */
- (void) save:(NSError**) error;

/**
 * Returns the camera's intrinsic parameters.
 */
- (CameraParameters) getCameraParameters;

@end
