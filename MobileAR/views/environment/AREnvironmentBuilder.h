// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.


#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>


@class AREnvironment;
@class ARPose;


/**
 Bridge between Swift and C++ spherical stitching.
 */
@interface AREnvironmentBuilder : NSObject

/**
 Creates a new spherical image builder.
 */
- (instancetype)initWithWidth:(size_t)width height:(size_t)height;

/**
 Updates the preview with a frame.
*/
- (void)update:(UIImage*)image pose:(ARPose*)pose;

/**
 Returns the preview image.
 */
- (UIImage*)getPreview;

@end