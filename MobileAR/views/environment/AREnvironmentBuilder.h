// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.


#import <CoreMedia/CoreMedia.h>
#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>


@class AREnvironment;
@class ARPose;
@class ARParameters;


/**
 Frame taken at multiple exposures.
 */
@interface ARHDRFrame : NSObject

@property (nonatomic) UIImage *frame;
@property (nonatomic) ARPose *pose;
@property (nonatomic) CMTime exposure;

/**
 Initializes the frame.
 */
- (instancetype)initWithFrame:(UIImage*)frame pose:(ARPose*)pose exposure:(CMTime)exposure;

@end


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
- (BOOL)update:(NSArray<ARHDRFrame*>*)frames error:(NSError**)error;

/**
 Composites the panorama.
 */
- (void)composite:(void(^)(NSString*, NSArray<UIImage*>*))progressBlock;

@end