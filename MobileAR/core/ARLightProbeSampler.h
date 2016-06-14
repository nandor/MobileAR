// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <UIKit/UIKit.h>

@class ARLight;
@class ARHDRImage;

/**
 Encapsulates and wraps light probe sampling logic.
 */
@interface ARLightProbeSampler : NSObject

/**
 Samples using variance cut sampling.
 */
+ (NSArray<ARLight*>*)sampleVarianceCutLDR:(UIImage*)image levels:(size_t)levels;

/**
 Samples using median cut sampling.
 */
+ (NSArray<ARLight*>*)sampleMedianCutLDR:(UIImage*)image levels:(size_t)levels;

/**
 Samples a HDR image using variance cut smapling.
 */
+ (NSArray<ARLight*>*)sampleVarianceCutHDR:(ARHDRImage*)image levels:(size_t)levels;

/**
 Samples a HDR image using median cut sampling.
 */
+ (NSArray<ARLight*>*)sampleMedianCutHDR:(ARHDRImage*)image levels:(size_t)levels;

@end