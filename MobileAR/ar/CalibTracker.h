// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#include "ar/Tracker.h"


namespace ar {

/**
 Tracker for the calibration pattern.
 */
class CalibTracker : public Tracker {
 public:
  /**
   Creates a calibration tracker.
   */
  CalibTracker(const cv::Mat k, const cv::Mat d);

  /**
   Destroys the calibration pattern tracker.
   */
  virtual ~CalibTracker();

 protected:
  /**
   Tracker-specific implementation of frame processing.
   */
  TrackingResult TrackFrameImpl(const cv::Mat &frame, float dt);

 private:
  // Reference grid.
  std::vector<cv::Point3f> grid_;
  
  // Temporary OpenCV mats.
  cv::Mat rvec_;
  cv::Mat tvec_;
};

}
