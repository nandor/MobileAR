// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <AVFoundation/AVFoundation.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>

#import "ARPoseTracker.h"

@class ARParameters;
@class ARPose;


/**
 Class responsible for tracking using a patterna and sensors.
 */
@interface ARSlamPoseTracker : NSObject<ARPoseTracker>

/**
 Initializes the tracker.
 */
- (instancetype)initWithParameters:(ARParameters *)params;

/**
 Updates the pose by tracking the new frame.
 */
- (void)trackFrame:(UIImage *)image;

/**
 Updates the tracker using sensor measurements.
 */
- (void)trackSensor:(CMAttitude *)x a:(CMAcceleration)a w:(CMRotationRate)w;

/**
 Returns the tracked pose.
 */
- (ARPose *)getPose;

@end