// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "ARMarkerPoseTracker.h"
#import "UIImage+cvMat.h"
#import "MobileAR-Swift.h"

#include <opencv2/opencv.hpp>
#include <Eigen/Eigen>

#include "ar/Rotation.h"
#include "ar/Tracker.h"
#include "ar/CalibTracker.h"
#include "ar/ArUcoTracker.h"


@implementation ARMarkerPoseTracker
{
  // OpenCV images & temporary matrices.
  cv::Mat rgba;
  cv::Mat gray;

  // Calibration parameters.
  cv::Mat cmat;
  cv::Mat dmat;

  // Timestamp to compute frame times.
  double prevTime;

  // Active tracker.
  std::shared_ptr<ar::Tracker> tracker;

  // List of initial candidate trackers.
  std::vector<std::shared_ptr<ar::Tracker>> trackers;
}

- (instancetype)initWithParameters:(ARParameters *)params
{
  if (!(self = [super init])) {
    return nil;
  }

  // Set up the intrinsic matrix.
  cmat = cv::Mat::zeros(3, 3, CV_64F);
  cmat.at<double>(0, 0) = params.fx;
  cmat.at<double>(1, 1) = params.fy;
  cmat.at<double>(0, 2) = params.cx;
  cmat.at<double>(1, 2) = params.cy;
  cmat.at<double>(2, 2) = 1.0f;

  // Set up the distortion parameters.
  dmat = cv::Mat::zeros(4, 1, CV_64F);
  dmat.at<double>(0, 0) = params.k1;
  dmat.at<double>(1, 0) = params.k2;
  dmat.at<double>(2, 0) = params.r1;
  dmat.at<double>(3, 0) = params.r2;

  // Initialize the timers.
  prevTime = CACurrentMediaTime();

  // Create a list of all tracker.
  trackers = {
    std::make_shared<ar::CalibTracker>(cmat, dmat),
    std::make_shared<ar::ArUcoTracker>(cmat, dmat)
  };

  return self;
}


- (BOOL)trackFrame:(UIImage *)image
{
  const float dt = [self deltaTime];

  [image toCvMat:rgba];
  cv::cvtColor(rgba, gray, CV_BGRA2GRAY);

  if (tracker) {
    return tracker->TrackFrame(gray, dt);
  } else {
    for (const auto &t : trackers) {
      if (t->TrackFrame(gray, dt)) {
        tracker = t;
        trackers.clear();
        return true;
      }
    }
    return false;
  }
}


- (void)trackSensor:(CMAttitude *)x a:(CMAcceleration)a w:(CMRotationRate)w
{
  const auto q = [x quaternion];

  if (tracker) {
    tracker->TrackSensor(
        { -q.w, -q.y,  q.x,  q.z },
        {  a.x,  a.y,  a.z },
        {  w.x,  w.y,  w.z },
        [self deltaTime]
    );
  }
}


- (ARPose *)getPose
{
  if (!tracker) {
    return nil;
  }

  // Extrinsic matrix - translation + rotation.
  const auto r = tracker->GetOrientation().toRotationMatrix();
  const auto t = tracker->GetPosition();
  
  // Pass the extrinsic matrix.
  NSArray<NSNumber*> *viewMat = @[
      @(r(0, 0)), @(r(1, 0)), @(r(2, 0)), @(0.0f),
      @(r(0, 1)), @(r(1, 1)), @(r(2, 1)), @(0.0f),
      @(r(0, 2)), @(r(1, 2)), @(r(2, 2)), @(0.0f),
      @(t(0, 0)), @(t(1, 0)), @(t(2, 0)), @(1.0f),
  ];
  
  // Pass the intrinsic matrix, converting to OpenGL depth convention.
  const float fx = cmat.at<double>(0, 0);
  const float fy = cmat.at<double>(1, 1);
  const float cx = cmat.at<double>(0, 2);
  const float cy = cmat.at<double>(1, 2);
  const float f = 500.0f;
  const float n = 0.1f;
  
  NSArray<NSNumber*> *projMat = @[
      @(fx / cx),    @(0.0f),                 @(0.0f), @( 0.0f),
         @(0.0f), @(fy / cy),                 @(0.0f), @( 0.0f),
         @(0.0f),    @(0.0f),   @(-(f + n) / (f - n)), @(-1.0f),
         @(0.0f),    @(0.0f), @(-2 * f * n / (f - n)), @( 0.0f)
  ];
  
  // Create the pose out of the view + projection matrix.
  return [[ARPose alloc] initWithViewMat:viewMat projMat:projMat];
}

/**
 Computes the time since the last update.
 */
- (double)deltaTime
{
  const double time = CACurrentMediaTime();
  const double dt = time - prevTime;
  prevTime = time;
  return dt;
}

/**
 Returns the markers tracked.
 */
- (NSArray<ARMarker*>*)getMarkers
{
  if (!tracker) {
    return [[NSArray alloc] init];
  }

  std::vector<ARMarker*> markers;
  for (const auto &marker : tracker->GetMarkers()) {
    assert(marker.size() == 4);
    markers.emplace_back([[ARMarker alloc]
        initWithP0:CGPointMake(marker[0].x, marker[0].y)
        p1:CGPointMake(marker[1].x, marker[1].y)
        p2:CGPointMake(marker[2].x, marker[2].y)
        p3:CGPointMake(marker[3].x, marker[3].y)
    ]);
  }

  return [[NSArray alloc] initWithObjects:&markers[0] count:markers.size()];
}

@end
