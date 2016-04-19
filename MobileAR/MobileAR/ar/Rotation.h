// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#pragma once

#include <Eigen/Eigen>
#include <Eigen/SVD>


namespace ar {

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

}
