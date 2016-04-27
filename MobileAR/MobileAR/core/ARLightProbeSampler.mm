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
}


+ (NSArray<ARLight*>*)sampleVarianceCut:(UIImage*)image levels:(size_t)levels
{
  return [ARLightProbeSampler sample: ar::VarianceCutSampler(levels, [image cvMat])];
}


+ (NSArray<ARLight*>*)sampleMedianCut:(UIImage*)image levels:(size_t)levels
{
  return [ARLightProbeSampler sample: ar::MedianCutSampler(levels, [image cvMat])];
}


+ (NSArray<ARLight*>*)sample:(ar::LightProbeSampler&&)sampler
{
  // Sample the light sources in the image.
  auto lights = sampler();

  // Convert light sources to Swift ARLight.
  std::vector<ARLight*> ptrs;
  for (const auto &light: lights) {
    ptrs.push_back([[ARLight alloc]
        initWithDirection: light.direction
        ambient: light.ambient
        diffuse: light.diffuse
        specular: light.specular
        x: light.centroidX
        y: light.centroidY
        area: light.area
    ]);
  }

  return [[NSArray alloc] initWithObjects: &ptrs[0] count: ptrs.size()];
}

@end