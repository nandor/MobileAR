// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#include <Eigen/Eigen>

#include "ar/Jet.h"


namespace ar {
  
/**
 Wrapper around Extended Kalman Filters.
 
 @tparam T Type of the data (usually float/double).
 @tparam N Number of elements in the state vector.
 @tparam WN Number of elements in the process noise covariance.
 */
template<typename T, size_t N, size_t WN>
class KalmanFilter {
 public:
  
  /**
   Creates the Kalman filter.
   */
  KalmanFilter(const Eigen::Matrix<T, WN, WN> &q)
    : q_(q)
  {
  }
  
  /**
   Creates the Kalman filter with an initial state and covariance.
   */
  KalmanFilter(
      const Eigen::Matrix<T, WN, WN> &q,
      const Eigen::Matrix<T, N, 1> &x,
      const Eigen::Matrix<T, N, N> &p)
    : q_(q)
    , x_(x)
    , p_(p)
  {
  }

  /**
   Destroys the Kalman filter.
   */
  virtual ~KalmanFilter() {
  }
  
  /**
   Performs an update on the Kalman Filter.
   */
  template<typename Updater, size_t M, size_t WM>
  void Update(
      const T &dt,
      const Eigen::Matrix<T, M, 1> zm,
      const Eigen::Matrix<T, WM, WM> &r)
  {
    
    // Convert the state to jet form, compute both the projected state and the Jacobian.
    // Extract the new state & the Jacobian matrix.
    Eigen::Matrix<T, N, 1> x;
    Eigen::Matrix<T, N, N> F;
    Eigen::Matrix<T, N, WN> WF;
    {
      Eigen::Matrix<Jet<T, N + WN>, N, 1> xjet;
      Eigen::Matrix<Jet<T, N + WN>, WN, 1> wjet;
      
      for (size_t i = 0; i < N; ++i) {
        xjet(i).s = x_(i);
        xjet(i).e(i) = 1;
      }
      for (size_t i = 0; i < WN; ++i) {
        wjet(i).s = 0;
        wjet(i).e(i + N) = 1;
      }
    
      const auto xj = Updater::Update(xjet, wjet, Jet<T, N + WN>(dt));
    
      for (size_t i = 0; i < N; ++i) {
        x(i) = xj(i).s;
        for (size_t j = 0; j < N; ++j) {
          F(i, j) = xj(i).e(j);
        }
        for (size_t j = 0; j < WN; ++j) {
          WF(i, j) = xj(i).e(j + N);
        }
      }
    }
    
    // Project ahead the covariance matrix.
    Eigen::Matrix<T, N, N> p = F * p_ * F.transpose() + WF * q_ * WF.transpose();
    
    // Extract the measurement vector and Jacobian.
    Eigen::Matrix<T, M, 1> z;
    Eigen::Matrix<T, M, N> H;
    Eigen::Matrix<T, M, WM> WH;
    {
      Eigen::Matrix<Jet<T, N + WM>, N, 1> zjet;
      Eigen::Matrix<Jet<T, N + WM>, WM, 1> wjet;
      for (size_t i = 0; i < N; ++i) {
        zjet(i).s = x(i);
        zjet(i).e(i) = 1;
      }
      for (size_t i = 0; i < WM; ++i) {
        wjet(i).s = 0;
        wjet(i).e(i + N) = 1;
      }
      
      const auto zj = Updater::Measure(zjet, wjet);
    
      for (size_t i = 0; i < M; ++i) {
        z(i) = zj(i).s;
        for (size_t j = 0; j < N; ++j) {
          H(i, j) = zj(i).e(j);
        }
        for (size_t j = 0; j < WM; ++j) {
          WH(i, j) = zj(i).e(j + N);
        }
      }
    }
    
    // Compute the Kalman gain.
    const auto k = p * H.transpose() * (
        H * p * H.transpose() + WH * r * WH.transpose()
    ).inverse();
    
    // Update the state estimate.
    x_ = x + k * (zm - z);
    
    // Update the covariance.
    p_ = (Eigen::Matrix<T, N, N>::Identity() - k * H) * p;
  }
  
  /**
   Returns the state.
   */
  Eigen::Matrix<T, N, 1> GetState() {
    return x_;
  }
  
 private:
  /// Covariance matrix.
  const Eigen::Matrix<T, WN, WN> q_;
  
  /// State vector.
  Eigen::Matrix<T, N, 1> x_;
  /// Process noise.
  Eigen::Matrix<T, N, N> p_;
};

}