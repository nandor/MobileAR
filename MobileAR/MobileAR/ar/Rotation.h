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

  virtual bool ComputeJacobian(const double *x, double *J) const {
    J[0] =  x[3]; J[1]  =  x[2]; J[2]  = -x[1];
    J[3] = -x[2]; J[4]  =  x[3]; J[5]  =  x[0];
    J[6] =  x[1]; J[7]  = -x[0]; J[8]  =  x[3];
    J[9] = -x[0]; J[10] = -x[1]; J[11] = -x[2];
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
Parametrization for unit vectors.
*/
class UnitVectorParametrization : public ceres::LocalParameterization {
 public:
  virtual bool Plus(
      const double* x_raw,
      const double* delta_raw,
      double* x_plus_delta_raw) const
  {
    // Map the parameters.
    const Eigen::Map<const Eigen::Vector3d> x(x_raw);
    const Eigen::Map<const Eigen::Vector2d> delta(delta_raw);
    Eigen::Map<Eigen::Vector3d> x_plus_delta(x_plus_delta_raw);
    
    // Find the coordiantes on the sphere.
    const double u = 0.5 / M_PI * std::atan2(x(1), x(0));
    const double v = 0.5 - std::asin(x(2)) / M_PI;

    // Compute partial derivatives.
    Eigen::Vector3d dSdu(
        -std::cos(u) * std::cos(v),
        -std::cos(u) * std::sin(v),
        +std::sin(u)
    );
    Eigen::Vector3d dSdv(
        -std::cos(u) * std::sin(v),
        -std::cos(u) * std::cos(v),
        0.0
    );

    // Move the vector along the partial derivatives.
    x_plus_delta = x + dSdu.normalized() * delta(0) + dSdv.normalized() * delta(1);
    return true;
  }

  virtual bool ComputeJacobian(const double *x, double *J) const {
    // Find the coordiantes on the sphere.
    const double u = 0.5 / M_PI * std::atan2(x[1], x[0]);
    const double v = 0.5 - std::asin(x[2]) / M_PI;

    // Compute the Jacobian.
    J[0] = -std::cos(u) * std::cos(v); J[1] = -std::cos(u) * std::sin(v);
    J[2] = -std::cos(u) * std::sin(v); J[3] = -std::cos(u) * std::cos(v);
    J[4] = +std::sin(u);               J[5] = 0.0;
    return true;
  }
  
  virtual int GlobalSize() const {
    return 3;
  }

  virtual int LocalSize() const {
    return 2;
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