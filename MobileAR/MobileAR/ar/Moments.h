// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#include <opencv2/opencv.hpp>


namespace ar {

/**
 Region for a query.
 */
struct Region {
  
  const int x0;
  const int y0;
  const int x1;
  const int y1;

  Region(int y0, int x0, int y1, int x1)
    : x1(x1)
    , y1(y1)
    , x0(x0)
    , y0(y0)
  {
    assert(0 <= x0 && x0 <= x1);
    assert(0 <= y0 && y0 <= y1);
  }
  
  int area() const {
    return (y1 - y0 + 1) * (x1 - x0 + 1);
  }
  
  int width() const {
    return x1 - x0 + 1;
  }
  
  int height() const {
    return y1 - y0 + 1;
  }
};
  

/**
 Computes the nth power of x in a rather funny way.
 */
template<size_t N> inline int64_t power(int x) {
  const auto half = power<N >> 1>(x);
  const auto half2 = half * half;
  return (N & 1) ? (half2 * x) : half2;
}
template<> inline int64_t power<0>(int x) { return 1; }
template<> inline int64_t power<1>(int x) { return x; }
template<> inline int64_t power<2>(int x) { return x * x; }
  

/**
 Summed Square Table to efficiently compute moments in arbitrary regions.
 */
template<size_t I, size_t J>
class Moments {
 public:
  
  /**
   Creates a new table from an 8 bit luminance image.
   */
  Moments(const cv::Mat &image)
    : rows(image.rows)
    , cols(image.cols)
  {
    s_.resize(image.rows * image.cols);
    
    auto id0 = 0, id1 = 0;
    
    // First row of the SST. Copy from image.
    {
      const auto pow = power<I>(0);
      const auto row = image.ptr<uint8_t>(0);
      auto sum = 0ll;
      for (int x = 0; x < image.cols; ++x, ++id1) {
        sum += pow * power<J>(x) * static_cast<int64_t>(row[x]);
        s_[id1] = sum;
      }
    }

    // Keep indices of current and last rows.
    for (int y = 1; y < image.rows; ++y) {
      const auto row = image.ptr<uint8_t>(y);
      
      // Keep a running sum of current row.
      const auto pow = power<I>(y);
      auto sum = 0ll;
      
      // Increment running sum and sum with previous row.
      for (int x = 0; x < image.cols; ++x, ++id0, ++id1) {
        sum += pow * power<J>(x) * static_cast<int64_t>(row[x]);
        s_[id1] = s_[id0] + sum;
      }
    }
  }

  /**
   Nothing to do here.
   */
  virtual ~Moments() {
  }

  /**
   Returns the sum in a region.
   */
  inline int64_t operator() (const Region& r) const {
    assert(r.x1 < cols && r.y1 < rows);
    
    const auto y10 = r.y1, y01 = r.y0 - 1;
    const auto x10 = r.x1, x01 = r.x0 - 1;
    
    return
        +((y10 < 0 || x10 < 0) ? 0 : s_[y10 * cols + x10])
        -((y10 < 0 || x01 < 0) ? 0 : s_[y10 * cols + x01])
        +((y01 < 0 || x01 < 0) ? 0 : s_[y01 * cols + x01])
        -((y01 < 0 || x10 < 0) ? 0 : s_[y01 * cols + x10]);
  }

 private:
  /// Number of rows.
  int rows;
  /// Number of cols.
  int cols;
  /// R x C partial sums.
  std::vector<int64_t> s_;
};

}
