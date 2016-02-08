// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "MobileAR-Swift.h"
#import "UIImage+cvMat.h"

#include <memory>

#include "LightProbeSampler.h"
#include "MedianCutSampler.h"
#include "VarianceCutSampler.h"


@implementation ARLightProbeSampler
{
  std::unique_ptr<ar::LightProbeSampler> sampler;
}


- (instancetype)initVarianceCutSampler:(size_t)levels
{
  if (!(self = [super init])) {
    return nil;
  }
  sampler = std::make_unique<ar::VarianceCutSampler>(levels);
  return self;
}

- (instancetype)initMedianCutSampler:(size_t)levels
{
  if (!(self = [super init])) {
    return nil;
  }
  sampler = std::make_unique<ar::MedianCutSampler>(levels);
  return self;
}

- (NSArray<ARLight*>*)sample:(UIImage*)image
{
  // Sample the light sources in the image.
  cv::Mat mat;
  [image toCvMat:mat];
  auto lights = sampler->sample(mat);

  // Convert light sources to Swift ARLight.
  std::vector<ARLight*> ptrs;
  for (const auto &light: lights) {
    ptrs.push_back([[ARLight alloc]
        initWithDirection: light.direction
        ambient: light.ambient
        diffuse: light.diffuse
        specular: light.specular
    ]);
  }

  return [[NSArray alloc] initWithObjects: &ptrs[0] count: ptrs.size()];
}

@end