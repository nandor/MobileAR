// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <UIKit/UIKit.h>

@class ARLight;

/**
 Encapsulates and wraps light probe sampling logic.
 */
@interface ARLightProbeSampler : NSObject

/**
 Creates a new Variance Cut Sampler.
 */
+ (NSArray<ARLight*>*)sampleVarianceCut:(UIImage*)image levels:(size_t)levels;

/**
 Initializes a new Median Cut Sampler.
 */
+ (NSArray<ARLight*>*)sampleMedianCut:(UIImage*)image levels:(size_t)levels;

@end