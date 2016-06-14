// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <Foundation/Foundation.h>

#import "ARHDRImage.h"

#include <opencv2/opencv.hpp>



/**
 A category to extend the HDR buffers with an OpenCV interface.
 
 It is assumed that the images are 3-channel floating point matrices.
 */
@interface ARHDRImage (cvMat)

/**
 Creates a HDR image from an OpenCV matrix.
 */
+ (ARHDRImage *)imageWithCvMat:(const cv::Mat &)mtx;

/**
 Returns a cv matrix.
 */
- (cv::Mat)cvMat;

@end
