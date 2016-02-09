// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>

@class ARPose;

@protocol ARPoseTracker <NSObject>

- (void)trackFrame:(UIImage *)image;
- (ARPose *)getPose;
- (void)trackSensor:(CMAttitude *)attitude acceleration:(CMAcceleration)acceleration;

@end
