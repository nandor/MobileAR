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

 protected:
  /// Covariance matrix.
  const Eigen::Matrix<T, WN, WN> q_;

  /// State vector.
  Eigen::Matrix<T, N, 1> x_;
  /// Process noise.
  Eigen::Matrix<T, N, N> p_;
};

  

/**
 Kalman filter fusing orientation measurements.

 @tparam T Datatype used by the filter.
 */
template<typename T>
class EKFOrientation : public KalmanFilter<T, 10, 10> {
 private:
  /**
   Shared state update function.
   */
  struct EKFUpdate {
    template<typename S>
    static Eigen::Matrix<S, 10, 1> Update(
        const Eigen::Matrix<S, 10, 1> &x,
        const Eigen::Matrix<S, 10, 1> &w,
        const S &dt)
    {
      // Extract rotation data from the state.
      Eigen::Quaternion<S> rq(x(3), x(0), x(1), x(2));
      Eigen::Matrix<S, 3, 1> rv(x(4), x(5), x(6));
      Eigen::Matrix<S, 3, 1> ra(x(7), x(8), x(9));

      // Normalize if necessary.
      if (rq.norm() > S(1e-6)) {
        rq.normalize();
      }

      // Update the angular velocity and the rotation.
      Eigen::Matrix<S, 3, 1> r = S(0.5) * (rv * dt + ra * dt * dt / S(2));
      rv = rv + ra * dt;
      rq = Eigen::Quaternion<S>(S(0), r(0), r(1), r(2)) * rq;

      // Repack data into the state vector.
      return (Eigen::Matrix<S, 10, 1>() <<
          x(0) + rq.x(),
          x(1) + rq.y(),
          x(2) + rq.z(),
          x(3) + rq.w(),
          rv(0), rv(1), rv(2),
          ra(0), ra(1), ra(2)
      ).finished() + w;
    }
  };

  /**
   State update & measurement function for a sensor measurement.
   */
  struct EKFSensorUpdate : public EKFUpdate {
    template<typename S>
    static Eigen::Matrix<S, 7, 1> Measure(
        const Eigen::Matrix<S, 10, 1> &x,
        const Eigen::Matrix<S, 7, 1> &w)
    {
      Eigen::Quaternion<S> rq(x(3), x(0), x(1), x(2));
      if (rq.norm() > S(1e-6)) {
        rq.normalize();
      }
      return (Eigen::Matrix<S, 7, 1>() <<
          rq.x(), rq.y(), rq.z(), rq.w(),
          x(4), x(5), x(6)
      ).finished() + w;
    }
  };

  /**
   State update & measurement function for a marker measurement.
   */
  struct EKFMarkerUpdate : public EKFUpdate {
    template<typename S>
    static Eigen::Matrix<S, 4, 1> Measure(
        const Eigen::Matrix<S, 10, 1> &x,
        const Eigen::Matrix<S, 4, 1> &w)
    {
      Eigen::Quaternion<S> rq(x(3), x(0), x(1), x(2));
      if (rq.norm() > S(1e-6)) {
        rq.normalize();
      }
      return (Eigen::Matrix<S, 4, 1>() <<
          rq.x(), rq.y(), rq.z(), rq.w()
      ).finished() + w;
    }
  };

 public:
  /**
   Creates the Kalman filter.
   */
  EKFOrientation()
    : KalmanFilter<T, 10, 10>(
        (Eigen::Matrix<T, 10, 1>() <<
          5e-2, 5e-2, 5e-2, 5e-2, 1e-4, 1e-4, 1e-4, 1e-4, 1e-4, 1e-4
        ).finished().asDiagonal(),
        (Eigen::Matrix<T, 10, 1>() <<
          0, 1, 0, 0, 0, 0, 0, 0, 0, 0
        ).finished(),
        (Eigen::Matrix<T, 10, 1>() <<
          10, 10, 10, 10, 10, 10, 10, 10, 10, 10
        ).finished().asDiagonal()
      )
  {
    // Marker measurement noise.
    Eigen::Matrix<T, 4, 1> rM;
    rM << 1e-2, 1e-2, 1e-2, 1e-2;
    rM_ = rM.asDiagonal();

    // IMU measurement noise.
    Eigen::Matrix<T, 7, 1> rI;
    rI << 1e-2, 1e-2, 1e-2, 1e-2, 1e-2, 1e-2, 1e-2;
    rI_ = rI.asDiagonal();
  }

  /**
   Updates the filter with a measurement from the tracker.
   */
  void UpdateMarker(
      const Eigen::Quaternion<T> &q,
      const T &dt)
  {
    KalmanFilter<T, 10, 10>::template Update<EKFMarkerUpdate, 4, 4>(dt, (
        Eigen::Matrix<T, 4, 1>() << q.x(), q.y(), q.z(), q.w()
    ).finished(), rM_);
  }

  /**
   Updates the filter with a measurement from the IMU.
   */
  void UpdateIMU(
      const Eigen::Quaternion<T> &q,
      const Eigen::Matrix<T, 3, 1> &w,
      const T &dt)
  {
    KalmanFilter<T, 10, 10>::template Update<EKFSensorUpdate, 7, 7>(dt, (
        Eigen::Matrix<T, 7, 1>() << q.x(), q.y(), q.z(), q.w(), w(0), w(1), w(2)
    ).finished(), rI_);
  }

  /**
   Returns the orientation.
   */
  Eigen::Quaternion<T> GetOrientation() const {
    const auto &x = KalmanFilter<T, 10, 10>::x_;
    return Eigen::Quaternion<T>(x(3), x(0), x(1), x(2)).normalized();
  }

 private:
  /// Measurement noise for tracker.
  Eigen::Matrix<T, 4, 4> rM_;
  /// Measurement noise for IMU.
  Eigen::Matrix<T, 7, 7> rI_;
};
  
  
  
/**
 Kalman filter for position measurements
 */
template<typename T>
class EKFPosition : public KalmanFilter<T, 9, 9> {
 private:
  /**
   Shared state update function.
   */
  struct EKFUpdate {
    template<typename S>
    static Eigen::Matrix<S, 9, 1> Update(
        const Eigen::Matrix<S, 9, 1> &x,
        const Eigen::Matrix<S, 9, 1> &w,
        const S &dt)
    {
      // Extract position data from the state.
      Eigen::Matrix<S, 3, 1> px(x(0), x(1), x(2));
      Eigen::Matrix<S, 3, 1> pv(x(3), x(4), x(5));
      Eigen::Matrix<S, 3, 1> pa(x(6), x(7), x(8));
      
      // Update the position and velocity.
      px = px + pv * dt + pa * dt * dt * S(0.5);
      pv = pv + pa * dt;
      
      // Repack data into the state vector.
      return (Eigen::Matrix<S, 9, 1>() << px, pv, pa).finished() + w;
    }
  };
  
  /**
   State update & measurement function for a sensor measurement.
   */
  struct EKFSensorUpdate : public EKFUpdate {
    template<typename S>
    static Eigen::Matrix<S, 3, 1> Measure(
        const Eigen::Matrix<S, 9, 1> &x,
        const Eigen::Matrix<S, 3, 1> &w)
    {
      Eigen::Matrix<S, 3, 1> px(x(6), x(7), x(8));
      return px + w;
    }
  };
  
  /**
   State update & measurement function for a marker measurement.
   */
  struct EKFMarkerUpdate : public EKFUpdate {
    template<typename S>
    static Eigen::Matrix<S, 3, 1> Measure(
        const Eigen::Matrix<S, 9, 1> &x,
        const Eigen::Matrix<S, 3, 1> &w)
    {
      Eigen::Matrix<S, 3, 1> px(x(0), x(1), x(2));
      return px + w;
    }
  };

 public:
  /**
   Creates the Kalman filter.
   */
  EKFPosition()
    : KalmanFilter<T, 9, 9>(
        (Eigen::Matrix<T, 9, 1>() <<
           5e-2, 5e-2, 5e-2, 2e-1, 2e-1, 2e-1, 5e-2, 5e-2, 5e-2
        ).finished().asDiagonal(),
        (Eigen::Matrix<T, 9, 1>() <<
           0, 0, 0, 0, 0, 0, 0, 0, 0
        ).finished(),
        (Eigen::Matrix<T, 9, 1>() <<
          10, 10, 10, 10, 10, 10, 10, 10, 10
        ).finished().asDiagonal()
      )
  {
    rM_ <<
      5e-2,    0,    0,
         0, 5e-2,    0,
         0,    0, 5e-2;
    rI_ <<
      5e-2,    0,    0,
         0, 5e-2,    0,
         0,    0, 5e-2;
  }

  /**
   Updates the filter with a marker pose estimate.
   */
  void UpdateMarker(const Eigen::Matrix<T, 3, 1> &x, const T& dt) {
    KalmanFilter<T, 9, 9>::template Update<EKFMarkerUpdate, 3, 3>(dt, x, rM_);
  }
  
  /**
   Updates the filter with an IMU pose estimate.
   */
  void UpdateIMU(const Eigen::Matrix<T, 3, 1> &a, const T& dt) {
    KalmanFilter<T, 9, 9>::template Update<EKFSensorUpdate, 3, 3>(dt, a, rI_);
  }
  
  /**
   Returns the position.
   */
  Eigen::Matrix<T, 3, 1> GetPosition() const {
    const auto &x = KalmanFilter<T, 9, 9>::x_;
    return Eigen::Matrix<T, 3, 1>(x(0), x(1), x(2));
  }
  
 private:
  /// Measurement noise for tracker.
  Eigen::Matrix<T, 3, 3> rM_;
  /// Measurement noise for IMU.
  Eigen::Matrix<T, 3, 3> rI_;
};
  
}
