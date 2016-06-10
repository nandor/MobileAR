// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "AREnvironmentBuilder.h"
#import "UIImage+cvMat.h"
#import "MobileAR-Swift.h"

#include <unordered_map>

#include <ceres/ceres.h>
#include <opencv2/opencv.hpp>
#include <simd/simd.h>


#include "ar/EnvironmentBuilder.h"
#include "ar/Rotation.h"


/**
 Converts a SIMD matrix to an Eigen matrix.
 */
template<typename T>
Eigen::Matrix<T, 3, 3> ToEigen(const simd::float4x4 &m) {
  return (Eigen::Matrix<T, 3, 3>() <<
      T(m.columns[0].x), T(m.columns[1].x), T(m.columns[2].x),
      T(m.columns[0].y), T(m.columns[1].y), T(m.columns[2].y),
      T(m.columns[0].z), T(m.columns[1].z), T(m.columns[2].z)
  ).finished();
}

/**
 Converts an Eigen matrix to a SIMD matrix.
 */
simd::float4x4 ToSIMD(const Eigen::Matrix<float, 3, 3> &r) {
  return simd::float4x4(
      simd::float4{ r(0, 0), r(1, 0), r(2, 0), 0.0f },
      simd::float4{ r(0, 1), r(1, 1), r(2, 1), 0.0f },
      simd::float4{ r(0, 2), r(1, 2), r(2, 2), 0.0f },
      simd::float4{    0.0f,    0.0f,    0.0f, 1.0f }
  );
}



@implementation AREnvironmentMap

- (instancetype)initWithMap:(UIImage*)map exposure:(float)exposure
{
  if (!(self = [super init])) {
    return nil;
  }

  self.map = map;
  self.exposure = exposure;
  return self;
}

@end



@implementation ARHDRFrame
{
}

- (instancetype)initWithFrame:(UIImage*)frame pose:(ARPose*)pose exposure:(CMTime)exposure
{
  if (!(self = [super init])) {
    return nil;
  }

  self.frame = frame;
  self.pose = pose;
  self.exposure = exposure;
  return self;
}

@end


@implementation AREnvironmentBuilder
{
  // Panoramic stitcher.
  std::unique_ptr<ar::EnvironmentBuilder> builder;
}


- (instancetype)initWithParams:(ARParameters *)params width:(size_t)width height:(size_t)height
{
  if (!(self = [super init])) {
    return nil;
  }

  // Initialize the panoramic builder.
  {
    // OpenCV is 'special'.
    cv::Mat k = cv::Mat::zeros(3, 3, CV_32F);
    k.at<float>(0, 0) = params.fx;
    k.at<float>(1, 1) = params.fy;
    k.at<float>(2, 2) = 1.0f;
    k.at<float>(0, 2) = params.cx;
    k.at<float>(1, 2) = params.cy;
    cv::Mat d = cv::Mat::zeros(4, 1, CV_32F);
    d.at<float>(0) = params.k1;
    d.at<float>(1) = params.k2;
    d.at<float>(2) = params.r1;
    d.at<float>(3) = params.r2;

    // Finally.
    builder = std::make_unique<ar::EnvironmentBuilder>(width, height, k, d);
  }
  
  return self;
}

- (BOOL)update:(NSArray<ARHDRFrame*>*)frames error:(NSError**)error
{

  try {
    // Convert the Obj-C frames to C++ structures.
    std::vector<ar::HDRFrame> cframes;
    for (ARHDRFrame* frame in frames) {
      cv::Mat bgr;
      [[frame frame] toCvMat: bgr];
      cframes.emplace_back(
          bgr,
          ToEigen<float>([frame.pose proj]),
          ToEigen<float>([frame.pose view]),
          CMTimeGetSeconds(frame.exposure)
      );
    }

    // Add the image to the panorama & handle errors.
    builder->AddFrames(cframes);
    return YES;
  } catch (const ar::EnvironmentBuilderException &ex) {
    // Extract the error from C++ land.
    switch (ex.GetError()) {
      case ar::EnvironmentBuilderException::BLURRY:
        *error = [NSError errorWithDomain:ARCaptureErrorDomain code:ARCaptureErrorBlurry userInfo:nil];
        break;
        
      case ar::EnvironmentBuilderException::NOT_ENOUGH_FEATURES:
        *error = [NSError errorWithDomain:ARCaptureErrorDomain code:ARCaptureErrorNotEnoughFeatures userInfo:nil];
        break;

      case ar::EnvironmentBuilderException::NO_PAIRWISE_MATCHES:
        *error = [NSError errorWithDomain:ARCaptureErrorDomain code:ARCaptureErrorNoPairwiseMatches userInfo:nil];
        break;

      case ar::EnvironmentBuilderException::NO_GLOBAL_MATCHES:
        *error = [NSError errorWithDomain:ARCaptureErrorDomain code:ARCaptureErrorNoGlobalMatches userInfo:nil];
        break;
    }
    return NO;
  } catch (...) {
    return NO;
  }
}


- (void)composite:(void(^)(NSString*, NSArray<AREnvironmentMap*>*))progressBlock;
{
  // Run the task on a background queue.
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
    // Build the panorama & convert progress messages.
    auto results = builder->Composite([&progressBlock](const std::string &message) {
      dispatch_async(dispatch_get_main_queue(), ^{ progressBlock(@(message.c_str()), nil);});
    });

    // Convert the envmaps to Objective C types.
    std::vector<AREnvironmentMap*> envmaps;
    for (const auto &result : results) {
      UIImage *image = [UIImage imageWithCvMat:result.first];
      envmaps.push_back([[AREnvironmentMap alloc] initWithMap:image exposure:result.second]);
    }

    // Pass the array to the callback.
    dispatch_async(dispatch_get_main_queue(), ^{
      progressBlock(
          @"Finished",
          [[NSArray<AREnvironmentMap*> alloc] initWithObjects:&envmaps[0] count:envmaps.size()]
      );
    });
  });
}

@end
