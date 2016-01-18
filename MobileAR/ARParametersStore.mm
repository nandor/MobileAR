// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "ARParametersStore.h"


@implementation ARParametersStore
{
  NSString *path_;

  BOOL loaded_;

  CameraParameters cameraParameters_;
}


- (instancetype) initWithPath:(NSString*) path
{
  if (!(self = [super init])) {
    return nil;
  }

  path_ = path;
  loaded_ = NO;
  return self;
}


- (BOOL) load
{
  // Load the saved dictionary.
  NSDictionary *dict;
  if ((dict = [NSDictionary dictionaryWithContentsOfFile:path_]) == nil) {
    return NO;
  }

  // Load the camera parameters.
  NSDictionary *obj;
  if ((obj = dict[@"camera_parameters"]) == nil) {
    return NO;
  }

  cameraParameters_.fx = [obj[@"fx"] floatValue];
  cameraParameters_.fy = [obj[@"fy"] floatValue];
  cameraParameters_.cx = [obj[@"cx"] floatValue];
  cameraParameters_.fy = [obj[@"cy"] floatValue];
  cameraParameters_.k1 = [obj[@"k1"] floatValue];
  cameraParameters_.k2 = [obj[@"k2"] floatValue];
  cameraParameters_.k3 = [obj[@"k3"] floatValue];
  cameraParameters_.r1 = [obj[@"r1"] floatValue];
  cameraParameters_.r2 = [obj[@"r2"] floatValue];
}


- (void) save
{
  NSDictionary *dict = @{
      @"camera_parameters": @{
          @"fx": @(cameraParameters_.fx),
          @"fy": @(cameraParameters_.fy),
          @"cx": @(cameraParameters_.cx),
          @"cy": @(cameraParameters_.cy),
          @"k1": @(cameraParameters_.k1),
          @"k2": @(cameraParameters_.k2),
          @"k3": @(cameraParameters_.k3),
          @"r1": @(cameraParameters_.r1),
          @"r2": @(cameraParameters_.r2)
      }
  };

  [dict writeToFile:path_ atomically:YES];
}


- (CameraParameters) getCameraParameters
{
  return cameraParameters_;
}


- (void) setCameraParameters:(CameraParameters) cameraParameters
{
  cameraParameters_ = cameraParameters;
}


@end