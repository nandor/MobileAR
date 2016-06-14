// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "ARHDRImage.h"

#include <memory>
#include <iostream>


@implementation ARHDRImage
{
  std::unique_ptr<float[]> data_;
}

- (instancetype)initWithMatrix:(const float*)data width:(int)width height:(int)height
{
  return [self initWithMatrix:data width:width height:height stride: width * sizeof(float)];
}

- (instancetype)initWithMatrix:(const float*)data width:(int)width height:(int)height stride:(size_t)stride
{
  if (!(self = [super init])) {
    return nil;
  }

  // Save attributes.
  self.width = width;
  self.height = height;
  self.stride = stride;

  // Save the contents.
  data_ = std::make_unique<float[]>(stride * height);
  memcpy(data_.get(), data, stride * height);
  return self;
}

- (instancetype)initWithData:(NSData*)data
{
  if (!(self = [super init])) {
    return nil;
  }

  // Read the attributes.
  size_t location = 0;
  {
    int width;
    [data getBytes:&width range:NSMakeRange(location, sizeof(int))];
    self.width = width;
    location += sizeof(int);

    int height;
    [data getBytes:&height range:NSMakeRange(location, sizeof(int))];
    self.height = height;
    location += sizeof(int);

    size_t stride;
    [data getBytes:&stride range:NSMakeRange(location, sizeof(size_t))];
    self.stride = stride;
    location += sizeof(size_t);
  }

  // Read the contents.
  data_ = std::make_unique<float[]>(self.stride * self.height);
  [data getBytes:data_.get() range:NSMakeRange(location, self.stride * self.height)];
  return self;
}

- (NSData*)data
{
  // Buffer must hold attributes + contents.
  const size_t capacity = sizeof(int) + sizeof(int) + sizeof(size_t) + self.height * self.stride;
  NSMutableData *data = [[NSMutableData alloc] initWithCapacity: capacity];

  // Write attributes.
  {
    int width = self.width;
    [data appendBytes:&width length:sizeof(int)];

    int height = self.height;
    [data appendBytes:&height length:sizeof(int)];

    size_t stride = self.stride;
    [data appendBytes:&stride length:sizeof(size_t)];
  }

  // Write contents.
  {
    [data appendBytes:data_.get() length:self.height * self.stride];
  }

  return data;
}

- (const float*)matrix
{
  return data_.get();
}

@end
