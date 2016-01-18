// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <Foundation/Foundation.h>

/**
 * The intrinsic parameters of the camera.
 */
struct CameraParameters
{
  // Focal distance.
  float fx;
  float fy;

  // Principal point.
  float cx;
  float cy;

  // Tangential distortion.
  float k1;
  float k2;
  float k3;

  // Radial distortion.
  float r1;
  float r2;

  CameraParameters()
    : fx(1.0f)
    , fy(1.0f)
    , cx(0.0f)
    , cy(0.0f)
    , k1(0.0f)
    , k2(0.0f)
    , k3(0.0f)
    , r1(0.0f)
    , r2(0.0f)
  {
  }
};


/**
 * Class that manages loading and storing the parameters into a file.
 */
@interface ARParametersStore : NSObject

/**
 * Initializes the store by providing its path.
 */
- (instancetype) initWithPath:(NSString*) path;

/**
 * Checks if the parameters have been loaded.
 */
- (BOOL) load;

/**
 * Saves the calibration parameters to the file.
 */
- (void) save;

/**
 * Returns the camera's intrinsic parameters.
 */
- (CameraParameters) getCameraParameters;

/**
 * Sets the camera's intrinsic parameters.
 */
- (void) setCameraParameters:(CameraParameters) cameraParameters;

@end
