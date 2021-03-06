// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include "VarianceCutSampler.h"


namespace ar {

VarianceCutSampler::VarianceCutSampler(size_t depth, const cv::Mat &image)
  : LightProbeSampler(depth, image)
  , m00_(illum_)
  , m01_(illum_)
  , m10_(illum_)
  , m02_(illum_)
  , m20_(illum_)
{
}
  
void VarianceCutSampler::split(const Region &region, int depth) {
  
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
    // Try a cut along Y.
    auto bestY = region.y0;
    auto bestVarY = std::numeric_limits<double>::max();
    {
      for (int y = region.y0 + 1; y <= region.y1 - 2; ++y) {
        const Region r0(region.y0, region.x0, y + 0, region.x1);
        const Region r1(y + 1, region.x0, region.y1, region.x1);
        const auto var = std::max(variance(r0), variance(r1));
        
        if (bestVarY > var) {
          bestY = y;
          bestVarY = var;
        }
      }
    }
    
    split({ region.y0, region.x0, bestY + 0, region.x1 }, depth + 1);
    split({ bestY + 1, region.x0, region.y1, region.x1 }, depth + 1);
  } else {
    // Try a cut along X.
    auto bestX = region.x0;
    auto bestVarX = std::numeric_limits<double>::max();
    {
      for (int x = region.x0 + 1; x <= region.x1 - 2; ++x) {
        const Region r0(region.y0, region.x0, region.y1, x + 0);
        const Region r1(region.y0, x + 1, region.y1, region.x1);
        const auto var = std::max(variance(r0), variance(r1));
        
        if (bestVarX > var) {
          bestX = x;
          bestVarX = var;
        }
      }
    }

    split({ region.y0, region.x0, region.y1, bestX + 0 }, depth + 1);
    split({ region.y0, bestX + 1, region.y1, region.x1 }, depth + 1);
  }
}
  

double VarianceCutSampler::variance(const Region &r) {
  
  const auto m00 = m00_(r);
  if (m00 == 0) {
    return 0.0;
  }
  
  const auto m01 = m01_(r);
  const auto m10 = m10_(r);
  const auto m02 = m02_(r);
  const auto m20 = m20_(r);
  
  const auto y = m10 / m00;
  const auto x = m01 / m00;
  
  return m20 + m02 - 2 * (x * m01 + y * m10) + m00 * (x * x + y * y);
}
  
  
}
