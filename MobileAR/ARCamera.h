// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <UIKit/UIKit.h>

#include <opencv2/opencv.hpp>


@interface ARCamera : NSObject

- (id)initWithCallback:(void(^)(cv::Mat))block;
- (void)start;
- (void)stop;

@end
