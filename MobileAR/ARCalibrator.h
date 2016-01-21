// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIImage.h>

@class ARParameters;

typedef void(^ARCalibratorProgressCallback)(float);
typedef void(^ARCalibratorCompleteCallback)(float, ARParameters *);


/**
 Class that encapsulates calibration logic.
 */
@interface ARCalibrator : NSObject

/**
 Initializes the calibrator object.
 */
- (instancetype)init;

/**
 Finds a pattern in a frame and highlights it.
 */
- (UIImage *)findPattern:(UIImage *)frame;

/**
 Sets the callback for calibration progress.
 */
- (void)onProgress:(ARCalibratorProgressCallback)callback;

/**
 Sets the callback for calibration completion.
 */
- (void)onComplete:(ARCalibratorCompleteCallback)callback;

@end