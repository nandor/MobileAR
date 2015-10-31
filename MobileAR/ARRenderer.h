// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <UIKit/UIKit.h>

#include <opencv2/opencv.hpp>


@interface ARRenderer : NSObject

- (id)initWithView:(UIView*)uiView;
- (void)render;
- (void)start;
- (void)stop;
- (void)update:(cv::Mat)texture K:(cv::Mat)K r:(cv::Mat)r t:(cv::Mat)t d:(cv::Mat)d;

@end
