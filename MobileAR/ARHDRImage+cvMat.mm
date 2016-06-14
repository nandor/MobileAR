// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "ARHDRImage+cvMat.h"

@implementation ARHDRImage (cvMat)

+ (ARHDRImage *)imageWithCvMat:(const cv::Mat &)mtx
{
  // Check the input matrix.
  assert(mtx.channels() == 3);
  assert(mtx.type() == CV_32FC3);

  // Create a buffer.
  const float *data = static_cast<float*>(static_cast<void*>(mtx.data));
  return [[ARHDRImage alloc] initWithMatrix:data width: mtx.cols height: mtx.rows stride: mtx.step[0]];
}

- (cv::Mat)cvMat
{
  return cv::Mat(
      self.height,
      self.width,
      CV_32FC3,
      const_cast<float*>([self matrix]),
      self.stride
  ).clone();
}

@end
