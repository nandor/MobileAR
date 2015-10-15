// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "UIImage+cvMat.h"

@implementation UIImage (cvMat)

+ (UIImage *)imageWithCvMat:(const cv::Mat &)mtx
{
  CGColorSpaceRef colorSpace;
  switch (mtx.elemSize()) {
    case 1: {
      colorSpace = CGColorSpaceCreateDeviceGray();
      break;
    }
    case 3: {
      colorSpace = CGColorSpaceCreateDeviceRGB();
      break;
    }
    default: {
      return nil;
    }
  }
  
  auto data = [NSData dataWithBytes:mtx.data length: mtx.step[0] * mtx.rows];
  auto provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
  CGImageRef imageRef = CGImageCreate(
      mtx.cols,                                      // width
      mtx.rows,                                      // height
      8,                                             // bits per component
      8 * mtx.elemSize(),                            // bits per pixel
      mtx.step[0],                                   // bytesPerRow
      colorSpace,                                    // colorspace
      kCGImageAlphaNone | kCGBitmapByteOrderDefault, // bitmap info
      provider,                                      // CGDataProviderRef
      NULL,                                          // decode
      false,                                         // should interpolate
      kCGRenderingIntentDefault                      // intent
  );

  // Getting UIImage from CGImage
  auto image = [UIImage imageWithCGImage: imageRef];

  CGImageRelease(imageRef);
  CGDataProviderRelease(provider);
  CGColorSpaceRelease(colorSpace);

  return image;
}

@end
