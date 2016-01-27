// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "UIImage+MTLTexture.h"

#include <memory>


@implementation UIImage (MTLTexture)


-(void) toMTLTexture:(id<MTLTexture>)texture
{
  auto width = CGImageGetWidth(self.CGImage);
  auto height = CGImageGetHeight(self.CGImage);

  if (width != texture.width || height != texture.height) {
    return;
  }

  auto bytesPerRow = CGImageGetBytesPerRow(self.CGImage);

  auto rawData = std::make_unique<uint8_t[]>(height * bytesPerRow);

  auto colorSpace = CGColorSpaceCreateDeviceRGB();
  auto context = CGBitmapContextCreate(
      rawData.get(),
      width,
      height,
      8,
      bytesPerRow,
      colorSpace,
      kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little
  );

  CGContextDrawImage(
      context,
      CGRectMake(0.0f, 0.0f, width, height),
      self.CGImage
  );

  [texture replaceRegion:MTLRegionMake2D(0, 0, width, height)
             mipmapLevel:0
                   slice:0
               withBytes:rawData.get()
             bytesPerRow:bytesPerRow
           bytesPerImage:height * bytesPerRow];

  CGColorSpaceRelease(colorSpace);
  CGContextRelease(context);
}

@end