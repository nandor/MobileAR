// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#include "ar/BlurDetector.h"


namespace ar {

BlurDetector::BlurDetector(int rows, int cols, int threshold)
  : rows_((rows >> 4) << 4)
  , cols_((cols >> 4) << 4)
  , threshold_(threshold)
  , levels({
    std::make_shared<Level>(rows_ >> 1, cols_ >> 1, 4),
    std::make_shared<Level>(rows_ >> 2, cols_ >> 2, 2),
    std::make_shared<Level>(rows_ >> 3, cols_ >> 3, 1)
  })
{
}


std::pair<float, float> BlurDetector::operator() (const cv::Mat &gray) {
  // Crop the image to a size that is multiple of 16.
  cv::Mat LL;
  gray({0, 0, cols_, rows_}).convertTo(LL, CV_32F);
  
  cv::Mat temp;
  cv::cvtColor(LL, temp, CV_GRAY2BGR);
  
  // Build the 3 levels of the pyramid.
  BuildLevel<1, 2>(           LL, levels[0]);
  BuildLevel<2, 1>(levels[0]->LL, levels[1]);
  BuildLevel<3, 0>(levels[1]->LL, levels[2]);
  
  // Count the number of different edge types.
  int Nedge = 0;
  int Nda = 0;
  int Nrg = 0;
  int Nbrg = 0;
  for (int r = 0; r < (rows_ >> 4); ++r) {
    const auto pE1 = levels[0]->EMax.ptr<float>(r);
    const auto pE2 = levels[1]->EMax.ptr<float>(r);
    const auto pE3 = levels[2]->EMax.ptr<float>(r);
    
    for (int c = 0; c < (cols_ >> 4); ++c) {
      const auto E1 = pE1[c], E2 = pE2[c], E3 = pE3[c];
      
      // Rule 1: Bail out if not an edge.
      if (E1 < threshold_ && E2 < threshold_ && E3 < threshold_) {
        continue;
      }
      
      Nedge++;
      
      // Rule 2: Dirac or A-Step.
      if (E1 > E2 && E2 > E3) {
        Nda++;
        continue;
      }
      
      // Rule 3, 4: Roof or G-Step.
      if ((E1 < E2 && E2 < E3) || (E1 < E2 && E3 < E2)) {
        Nrg++;
        if (E1 < threshold_) {
          Nbrg++;
        }
      }
    }
  }
  
  if (Nedge == 0 || Nrg == 0) {
    return { 0.0f, 0.0f };
  }
  
  const float per  = static_cast<float>(Nda)  / static_cast<float>(Nedge);
  const float blur = static_cast<float>(Nbrg) / static_cast<float>(Nrg);
  
  return { per, blur };
}

template<size_t N>
void BlurDetector::HaarTransform(
     const cv::Mat &LL0,
     cv::Mat &HH1,
     cv::Mat &LH1,
     cv::Mat &HL1,
     cv::Mat &LL1)
{
  for (int r = 0; r < rows_ >> N; ++r) {
    for (int c = 0; c < cols_ >> N; ++c) {
      const float p00 = LL0.at<float>((r << 1) + 0, (c << 1) + 0);
      const float p01 = LL0.at<float>((r << 1) + 0, (c << 1) + 1);
      const float p10 = LL0.at<float>((r << 1) + 1, (c << 1) + 0);
      const float p11 = LL0.at<float>((r << 1) + 1, (c << 1) + 1);
      
      HH1.at<float>(r, c) = (p00 + p11 - p10 - p01) * 0.5f;
      HL1.at<float>(r, c) = (p00 + p10 - p11 - p01) * 0.5f;
      LH1.at<float>(r, c) = (p00 + p01 - p10 - p11) * 0.5f;
      LL1.at<float>(r, c) = (p00 + p01 + p10 + p11) * 0.5f;
    }
  }
}

template<size_t N, size_t M>
void BlurDetector::LocalMaxima(const cv::Mat &EMap, cv::Mat &EMax) {
  for (int r0 = 0; r0 < rows_ >> (N + M); ++r0) {
    for (int c0 = 0; c0 < cols_ >> (N + M); ++c0) {
      float max = std::numeric_limits<float>::min();
      for (int dr = 0; dr < (1 << M); ++dr) {
        for (int dc = 0; dc < (1 << M); ++dc) {
          max = std::max(max, EMap.at<float>((r0 << M) + dr, (c0 << M) + dc));
        }
      }
      EMax.at<float>(r0, c0) = max;
    }
  }
}

template<size_t N, size_t M>
void BlurDetector::BuildLevel(const cv::Mat &LL0, const std::shared_ptr<Level> &l) {
  HaarTransform<N>(LL0, l->HH, l->LH, l->HL, l->LL);
  
  for (int r = 0; r < rows_ >> N; ++r) {
    auto pEMap = l->EMap.ptr<float>(r);
    
    const auto pHH = l->HH.ptr<float>(r);
    const auto pHL = l->HL.ptr<float>(r);
    const auto pLH = l->LH.ptr<float>(r);
    
    for (int c = 0; c < cols_ >> N; ++c) {
      pEMap[c] = pHH[c] * pHH[c] + pHL[c] * pHL[c] + pLH[c] * pLH[c];
    }
  }
  
  LocalMaxima<N, M>(l->EMap, l->EMax);
}
  
}