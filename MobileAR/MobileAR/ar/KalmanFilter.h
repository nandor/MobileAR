// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#include <Eigen/Eigen>


namespace ar {
  
  
/**
 Kalman filter fusing orientation measurements.
 
 @tparam T Datatype used by the filter.
 */
template<typename T>
class EKFOrientation {
 public:
  
  /**
   Creates the Kalman filter.
   */
  EKFOrientation() {
    // Initialise the state - all zero.
    x_ << 0, 1, 0, 0, 0, 0, 0, 0, 0, 0;
    
    // State noise - very high variance.
    Eigen::Matrix<T, 10, 1> p;
    p << 10, 10, 10, 10, 10, 10, 10, 10, 10, 10;
    p_ = p.asDiagonal();
    
    // Process noise covariance - quite low.
    Eigen::Matrix<T, 10, 1> q;
    q << 5e-2, 5e-2, 5e-2, 5e-2, 1e-4, 1e-4, 1e-4, 1e-4, 1e-4, 1e-4;
    q_ = q.asDiagonal();
    
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
    // Prediction step.
    Eigen::Matrix<T, 10, 1> x;
    Eigen::Matrix<T, 10, 10> p;
    std::tie(x, p) = Predict(dt);
    
    // Compute the residual and normalize it.
    Eigen::Quaternion<T> qy(x(0), x(1), x(2), x(3));
    if (qy.norm() > 1e-6) {
      qy.normalize();
    }
    Eigen::Matrix<T, 4, 1> y;
    y <<
      q.w() - qy.w(),
      q.x() - qy.x(),
      q.y() - qy.y(),
      q.z() - qy.z();
    
    // Compute the residual in matrix form & build the Jacobian withou
    // taking into account the normalization since that yields a hihgly
    // non-linear and unstable derivative.
    Eigen::Matrix<T, 4, 10> H;
    H <<
      1, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 1, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 1, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 1, 0, 0, 0, 0, 0, 0;
    
    // Compute the Kalman gain.
    const Eigen::Matrix<T, 4, 4> S = H * p * H.transpose() + rM_;
    const Eigen::Matrix<T, 10, 4> K = p * H.transpose() * S.inverse();
    
    // Update the state.
    x_ = x + K * y;
    p_ = (Eigen::Matrix<T, 10, 10>::Identity() - K * H) * p;
  }
  
  /**
   Updates the filter with a measurement from the IMU.
   */
  void UpdateIMU(
      const Eigen::Quaternion<T> &q,
      const Eigen::Matrix<T, 3, 1> &w,
      const T &dt)
  {
    // Prediction step.
    Eigen::Matrix<T, 10, 1> x;
    Eigen::Matrix<T, 10, 10> p;
    std::tie(x, p) = Predict(dt);
    
    // Compute the residual using the normalized vector.
    Eigen::Quaternion<T> qy(x(0), x(1), x(2), x(3));
    if (qy.norm() > 1e-6) {
      qy.normalize();
    }
    Eigen::Matrix<T, 7, 1> y;
    y <<
        q.w() - qy.w(),
        q.x() - qy.x(),
        q.y() - qy.y(),
        q.z() - qy.z(),
        w(0) - x(4),
        w(1) - x(5),
        w(2) - x(6);
    
    // Jacobian, returning quaternion and angular velocity.
    Eigen::Matrix<T, 7, 10> H;
    H <<
      1, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 1, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 1, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 1, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 1, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 1, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 1, 0, 0, 0;
    
    const Eigen::Matrix<T, 7, 7> S = H * p * H.transpose() + rI_;
    const Eigen::Matrix<T, 10, 7> K = p * H.transpose() * S.inverse();
    
    // Update the state.
    x_ = x + K * y;
    p_ = (Eigen::Matrix<T, 10, 10>::Identity() - K * H) * p;
  }
  
  /**
   Returns the orientation.
   */
  Eigen::Quaternion<T> GetOrientation() const {
    return Eigen::Quaternion<T>(x_(0), x_(1), x_(2), x_(3)).normalized();
  }
  
 private:
  /**
   Performs the prediction step of the filter.
   */
  std::pair<Eigen::Matrix<T, 10, 1>, Eigen::Matrix<T, 10, 10>> Predict(const T &dt) {
    
    // Decompose the state matrix.
    Eigen::Quaternion<T> rq(x_(0), x_(1), x_(2), x_(3));
    Eigen::Matrix<T, 3, 1> rv(x_(4), x_(5), x_(6));
    Eigen::Matrix<T, 3, 1> ra(x_(7), x_(8), x_(9));
    
    // Update the rotation, x1 = x0 + v0 * t + a * t * t / 2
    Eigen::Matrix<T, 3, 1> rr = T(0.5) * (rv * dt + ra * dt * dt * T(0.5));
    rq = Eigen::Quaternion<T>(T(0), rr(0), rr(1), rr(2)) * rq.normalized();
    rv = rv + dt * ra;
    
    // Compute the jacobian F = df(x)/dx.
    Eigen::Matrix<T, 10, 10> F;
    F <<
          1,   rr(0),  rr(1),  rr(2), 0, 0, 0,  0,  0,  0,
      -rr(0),      1, -rr(2),  rr(1), 0, 0, 0,  0,  0,  0,
      -rr(1),  rr(2),      1, -rr(0), 0, 0, 0,  0,  0,  0,
      -rr(2), -rr(1),  rr(0),      1, 0, 0, 0,  0,  0,  0,
           0,      0,      0,      0, 1, 0, 0, dt,  0,  0,
           0,      0,      0,      0, 0, 1, 0,  0, dt,  0,
           0,      0,      0,      0, 0, 0, 1,  0,  0, dt,
           0,      0,      0,      0, 0, 0, 0,  1,  0,  0,
           0,      0,      0,      0, 0, 0, 0,  0,  1,  0,
           0,      0,      0,      0, 0, 0, 0,  0,  0,  1;
    
    // Propagate the state. Addition done here since Eigen does not have it.
    Eigen::Matrix<T, 10, 1> x;
    x(0) = x_(0) + rq.w();
    x(1) = x_(1) + rq.x();
    x(2) = x_(2) + rq.y();
    x(3) = x_(3) + rq.z();
    x(4) = rv(0);  x(5) = rv(1);  x(6) = rv(2);
    x(7) = ra(0);  x(8) = ra(1);  x(9) = ra(2);
    
    // Propagate the noise.
    Eigen::Matrix<T, 10, 10> p = F * p_ * F.transpose() + q_;
    
    return { x, p };
  }
  
 private:
  /**
   The state of the EKF.
   
   0..3: quaternion orientation
   4..6: angular velocity
   7..9: angular acceleration.
   */
  Eigen::Matrix<T, 10, 1> x_;
  
  /// The process noise.
  Eigen::Matrix<T, 10, 10> p_;
  
  /// Process noise covariance.
  Eigen::Matrix<T, 10, 10> q_;
  
  /// Measurement noise for tracker.
  Eigen::Matrix<T, 4, 4> rM_;
  
  /// Measurement noise for IMU.
  Eigen::Matrix<T, 7, 7> rI_;
};

}