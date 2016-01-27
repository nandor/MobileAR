// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <AVFoundation/AVFoundation.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>

@interface ARSceneTracker : NSObject

/**
 Updates the pose by tracking the new frame.
 */
- (void)trackFrame:(UIImage *)image;

/**
 Updates the tracker using sensor measurements.
 */
- (void)trackSensor:(CMAttitude *)attitude acceleration:(CMAcceleration)acceleration;

@end