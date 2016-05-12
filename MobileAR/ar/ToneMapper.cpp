// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include "ar/ToneMapper.h"


namespace ar {

cv::Mat ToneMapper::map(const cv::Mat &img) const {

  // Compute the luminance.
  cv::Mat lw;
  switch (img.channels()) {
    case 4: {
      assert(img.type() == CV_32FC4);
      cv::cvtColor(img, lw, CV_BGRA2GRAY);
      break;
    }
    case 3: {
      assert(img.type() == CV_32FC3);
      cv::cvtColor(img, lw, CV_BGR2GRAY);
      break;
    }
    case 1: {
      assert(img.type() == CV_32FC1);
      lw = img;
      break;
    }
    default: {
      throw std::runtime_error("Image must be either RGB, RGBA or grayscale.");
    }
  }

  // Log-average intensity.
  float lm;
  {
    cv::Mat log(img.rows, img.cols, CV_32FC1);
    cv::log(lw + 1e-10, log);
    lm = std::exp(cv::sum(log)[0] / (log.rows * log.cols));
  }

  // Compute the scaled luminance.
  const cv::Mat ll = key_ / lm * lw;
  
  // Apply the tone mapping operator.
  cv::Mat ld(img.rows, img.cols, CV_32FC1);
  if (LWhite_ > 1e-3) {
    ld = ll * (1 + ll / (LWhite_ * LWhite_)) / (1 + ll);
  } else {
    ld = ll / (1 + ll);
  }
  
  // Convert to 8 bits/channel.
  switch (img.channels()) {
    case 1: {
      // Just convert & saturate at 8 bits.
      cv::Mat ldr8;
      ld.convertTo(ldr8, CV_8UC1, 255.0f);
      return ldr8;
    }
    case 3: case 4: {
      // Compute the scale factor.
      const cv::Mat scale = lw / ld;

      // Extract r, g, b.
      std::vector<cv::Mat> chan;
      cv::split(img, chan);

      // Scale r, g, b or whatever the hell the order is in OpenCV.
      cv::Mat r, g, b;
      cv::divide(chan[0], scale, r);
      cv::divide(chan[1], scale, g);
      cv::divide(chan[2], scale, b);

      // Convert to 8 bits, add alpha channel if necessary.
      cv::Mat ldr8, ldru8;
      cv::merge(std::vector<cv::Mat>{r, g, b}, ldr8);
      ldr8.convertTo(ldru8, CV_8UC3, 255.0f);
      if (img.channels() == 3) {
        return ldru8;
      } else {
        cv::Mat alpha;
        cv::cvtColor(ldru8, alpha, CV_BGR2BGRA);
        return alpha;
      }
    }
    default: {
      assert(0);
      return {};
    }
  }
}

}