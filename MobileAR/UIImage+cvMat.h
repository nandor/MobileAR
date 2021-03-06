// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <UIKit/UIKit.h>

#include <opencv2/opencv.hpp>

@interface UIImage (cvMat)

/**
 Creates a UIImage from an OpenCV matrix.
 */
+ (UIImage *)imageWithCvMat:(const cv::Mat &)mtx;

/**
 Converts a UIImage to an OpenCV matrix.
 */
- (void)toCvMat:(cv::Mat &)mtx;

/**
 Returns a cv matrix.
 */
- (cv::Mat)cvMat;

@end
