// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.


#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>


@class AREnvironment;
@class ARPose;
@class ARParameters;


/**
 Bridge between Swift and C++ spherical stitching.
 */
@interface AREnvironmentBuilder : NSObject

/**
 Creates a new spherical image builder.
 */
- (instancetype)initWithParams:(ARParameters*)params width:(size_t)width height:(size_t)height;

/**
 Updates the preview with a frame.
*/
- (BOOL)update:(UIImage*)image pose:(ARPose*)pose error:(NSError**)error;

@end