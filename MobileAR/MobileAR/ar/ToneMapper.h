// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#include <opencv2/opencv.hpp>


namespace ar {

/**
 Tone Mapping using the Reinhardt Global Operator.
 */
class ToneMapper {
 public:

  /**
   Initializes the tone mapper without burning whites.
   */
  ToneMapper(float key = 0.36, float LWhite_ = 0.0f)
    : key_(key)
    , LWhite_(0.0f)
  {
  }
  
  /**
   Maps an image from exponential HDR to LDR.
   */
  cv::Mat map(const cv::Mat &img) const;

 private:
  /// Key of the final image.
  const float key_;
  /// Maximal white intensity.
  const float LWhite_;
};

}
