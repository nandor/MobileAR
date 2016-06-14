// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "ARHDRBuilder.h"
#import "ARHDRImage+cvMat.h"
#import "UIImage+cvMat.h"

#include <vector>

#include <opencv2/opencv.hpp>

#include "ar/HDRBuilder.h"


@implementation ARHDRBuilder

+ (ARHDRImage*)build: (NSArray<AREnvironmentMap*>*) envmaps
{
  std::vector<std::pair<cv::Mat, float>> images;
  for (AREnvironmentMap *envmap in envmaps) {
    images.emplace_back([envmap.map cvMat], envmap.exposure);
  }
  return [ARHDRImage imageWithCvMat:ar::HDRBuilder().build(images)];
}

@end
