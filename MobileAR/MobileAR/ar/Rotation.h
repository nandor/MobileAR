// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#include <ceres/ceres.h>

#include <Eigen/Eigen>
#include <Eigen/SVD>


namespace ar {

/**
 Operator to update unit quaternions.
 */
class QuaternionParametrization : public ceres::LocalParameterization {
 public:

  virtual bool Plus(
        const double* x_raw,
        const double* delta_raw,
        double* x_plus_delta_raw) const
  {
    const Eigen::Map<const Eigen::Quaterniond> x(x_raw);
    const Eigen::Map<const Eigen::Vector3d > delta(delta_raw);
    Eigen::Map<Eigen::Quaterniond> x_plus_delta(x_plus_delta_raw);

    const double delta_norm = delta.norm();
    if ( delta_norm < 1e-10) {
      x_plus_delta = x;
      return true;
    }

    const double sin_delta_by_delta = std::sin(delta_norm) / delta_norm;
    Eigen::Quaterniond tmp(
        std::cos(delta_norm),
        sin_delta_by_delta * delta[0],
        sin_delta_by_delta * delta[1],
        sin_delta_by_delta * delta[2]
    );

    x_plus_delta = tmp * x;
    return true;
  }

  virtual bool ComputeJacobian(const double* x, double* jacobian) const {
    jacobian[0] =  x[3]; jacobian[1]  =  x[2]; jacobian[2]  = -x[1];
    jacobian[3] = -x[2]; jacobian[4]  =  x[3]; jacobian[5]  =  x[0];
    jacobian[6] =  x[1]; jacobian[7]  = -x[0]; jacobian[8]  =  x[3];
    jacobian[9] = -x[0]; jacobian[10] = -x[1]; jacobian[11] = -x[2];
    return true;
  }

  virtual int GlobalSize() const {
    return 4;
  }
  virtual int LocalSize() const {
    return 3;
  }
};


/**
 Computes the average of quaternions, minimizing the Froebnius norm of the poses.
 */
template<typename T>
Eigen::Quaternion<T> QuaternionAverage(const std::vector<Eigen::Quaternion<T>> &qis) {

  // Much math leads here.
  Eigen::Matrix<T, 4, 4> M = Eigen::Matrix<T, 4, 4>::Zero();
  for (const auto &qi : qis) {
    Eigen::Matrix<T, 4, 1> qv(qi.x(), qi.y(), qi.z(), qi.w());
    M += qv * qv.transpose();
  }
  
  // Compute the SVD of the matrix.
  Eigen::JacobiSVD<Eigen::Matrix<T, 4, 4>> svd(M, Eigen::ComputeFullU | Eigen::ComputeFullV);
  const auto q = svd.matrixU().col(0);
  return Eigen::Quaternion<T>(q(3), q(0), q(1), q(2));
}


/**
 Returns the rotation angle of a quaternion, in [-pi, pi]
 */
template<typename T>
T Angle(const Eigen::Quaternion<T> &q) {
  const T& angle = 2.0f * std::acos(q.w());
  return (angle > T(M_PI)) ? (angle - T(2.0 * M_PI)) : angle;
}

}