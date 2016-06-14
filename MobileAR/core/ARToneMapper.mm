// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "ARToneMapper.h"
#import "ARHDRImage+cvMat.h"
#import "UIImage+cvMat.h"

#include "ar/ToneMapper.h"



@implementation ARToneMapper

+ (UIImage*)map:(ARHDRImage*)hdr
{
  return [UIImage imageWithCvMat: ar::ToneMapper().map([hdr cvMat])];
}

@end
