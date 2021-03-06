// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include "MedianCutSampler.h"


namespace ar {

MedianCutSampler::MedianCutSampler(size_t depth, const cv::Mat &image)
  : LightProbeSampler(depth, image)
  , m00_(illum_)
  , m01_(illum_)
  , m10_(illum_)
{
}

void MedianCutSampler::split(const Region &region, int depth) {

  // If max depth was reached, return light source.
  if (depth >= depth_) {
    const double area = m00_(region);
    if (std::abs(area) < 1e-5) {
      lights_.push_back(sample(
          region,
          (region.y0 + region.y1) / 2,
          (region.x0 + region.x1) / 2
      ));
    } else {
      lights_.push_back(sample(
          region,
          static_cast<int>(m10_(region) / area),
          static_cast<int>(m01_(region) / area)
      ));
    }
    return;
  }

  if (width(region) < height(region)) {
    // Try best cut along Y.
    auto bestY = region.y0 + 1;
    auto bestDiffY = std::numeric_limits<double>::max();
    {

      for (int y = region.y0 + 1; y <= region.y1 - 2; ++y) {
        const Region r0(region.y0, region.x0, y, region.x1);
        const Region r1(y + 1, region.x0, region.y1, region.x1);
        
        const auto diff = std::abs(m00_(r0) - m00_(r1));
        if (diff < bestDiffY) {
          bestY = y;
          bestDiffY = diff;
        }
      }
    }
    
    split({ region.y0, region.x0, bestY + 0, region.x1 }, depth + 1);
    split({ bestY + 1, region.x0, region.y1, region.x1 }, depth + 1);
  } else {
    // Try best cut along X.
    auto bestX = region.x0;
    auto bestDiffX = std::numeric_limits<double>::max();
    {

      for (int x = region.x0 + 1; x <= region.x1 - 2; ++x) {
        const Region r0(region.y0, region.x0, region.y1, x);
        const Region r1(region.y0, x + 1, region.y1, region.x1);
        
        const auto diff = std::abs(m00_(r0) - m00_(r1));
        if (diff < bestDiffX) {
          bestX = x;
          bestDiffX = diff;
        }
      }
    }

    split({ region.y0, region.x0, region.y1, bestX + 0 }, depth + 1);
    split({ region.y0, bestX + 1, region.y1, region.x1 }, depth + 1);
  }
}

  
}
