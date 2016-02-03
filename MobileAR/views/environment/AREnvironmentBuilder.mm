// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "AREnvironmentBuilder.h"
#import "UIImage+cvMat.h"

#include <opencv2/opencv.hpp>


@implementation AREnvironmentBuilder
{
  // Width of the environment map.
  size_t width;
  // Height of the environment map.
  size_t height;
  
  // OpenCV matrix holding the map.
  cv::Mat preview;
}


- (instancetype) initWithWidth:(size_t)width_ height: (size_t)height_ {
  
  if (!(self = [super init])) {
    return nil;
  }
  
  width = width_;
  height = height_;
  preview = cv::Mat::zeros(
      static_cast<int>(width),
      static_cast<int>(height),
      CV_8UC3
  );

  return self;
}


- (void)update:(UIImage*)image attitude:(CMAttitude*)attitude {

}


- (UIImage*)getPreview {
  return [UIImage imageWithCvMat: preview];
}

@end