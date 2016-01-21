// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIImage.h>

@class ARParameters;

@protocol ARCalibratorDelegate <NSObject>

- (void) onProgress:(float)progress;
- (void) onComplete:(float)rms params:(ARParameters*)params;

@end


/**
 Class that encapsulates calibration logic.
 */
@interface ARCalibrator : NSObject

/**
 Initializes the calibrator object.
 */
- (instancetype)initWithDelegate:(id)delegate;

/**
 Finds a pattern in a frame and highlights it.
 */
- (UIImage *)findPattern:(UIImage *)frame;

@end