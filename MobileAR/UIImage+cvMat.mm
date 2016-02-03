// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "UIImage+cvMat.h"

@implementation UIImage (cvMat)

+ (UIImage *)imageWithCvMat:(const cv::Mat &)mtx
{
  uint32_t flags;
  CGColorSpaceRef colorSpace;
  
  switch (mtx.elemSize()) {
    case 1: {
      flags = kCGImageAlphaNone | kCGBitmapByteOrderDefault;
      colorSpace = CGColorSpaceCreateDeviceGray();
      break;
    }
    case 3: {
      flags = kCGImageAlphaNone | kCGBitmapByteOrderDefault;
      colorSpace = CGColorSpaceCreateDeviceRGB();
      break;
    }
    case 4: {
      flags = kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrderDefault;
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
      static_cast<size_t>(mtx.cols),                 // width
      static_cast<size_t>(mtx.rows),                 // height
      8,                                             // bits per component
      8 * mtx.elemSize(),                            // bits per pixel
      mtx.step[0],                                   // bytesPerRow
      colorSpace,                                    // colorspace
      flags,                                         // bitmap info
      provider,                                      // CGDataProviderRef
      nil,                                           // decode
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

- (void)toCvMat:(cv::Mat &)mtx
{
  CGColorSpaceRef colorSpace = CGImageGetColorSpace(self.CGImage);

  mtx.create(
      static_cast<int>(self.size.height),
      static_cast<int>(self.size.width),
      CV_8UC4
  );

  CGContextRef contextRef = CGBitmapContextCreate(
      mtx.data,
      static_cast<size_t>(mtx.cols),
      static_cast<size_t>(mtx.rows),
      8,
      mtx.step[0],
      colorSpace,
      kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault
  );
  CGContextDrawImage(contextRef, CGRectMake(0, 0, mtx.cols, mtx.rows), self.CGImage);
  CGContextRelease(contextRef);
}

@end
