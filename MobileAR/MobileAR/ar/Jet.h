// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

namespace ar {

/**
 * Jet, a number of the form:
 * x0 + x1 * e1 + x2 * e2 + ... + xn * en.
 */
template<typename T, size_t N>
class Jet {
 public:
  
  Jet()
    : s(0)
    , e(Eigen::Matrix<T, N, 1>::Zero())
  {
  }
  
  Jet(const T &s_)
    : s(s_)
    , e(Eigen::Matrix<T, N, 1>::Zero())
  {
  }

  Jet(const T &s_, size_t i) {
    s = s_;
    e = Eigen::Matrix<T, N, 1>::Zero();
    e[i] = static_cast<T>(1);
  }

  Jet(const T &s_, const Eigen::Matrix<T, N, 1> &e_)
    : s(s_)
    , e(e_)
  {
  }

  // Scalar part.
  T s;
  // Vector part.
  Eigen::Matrix<T, N, 1> e;
};

  
template<typename T, size_t N>
Jet<T, N> operator * (const Jet<T, N> &x, const Jet<T, N> &y) {
  return { x.s * y.s, x.s * y.e + y.s * x.e };
}
  

template<typename T, size_t N>
Jet<T, N> operator / (const Jet<T, N> &x, const Jet<T, N> &y) {
  const T s = x.s / y.s;
  return {
    s,
    (x.e - y.e * s) / y.s
  };
}

  
template<typename T, size_t N>
Jet<T, N> operator + (const Jet<T, N> &x, const Jet<T, N> &y) {
  return { x.s + y.s, x.e + y.e };
}

  
template<typename T, size_t N>
Jet<T, N> operator - (const Jet<T, N> &x, const Jet<T, N> &y) {
  return { x.s - y.s, x.e - y.e };
}
  
  
template<typename T, size_t N>
bool operator < (const Jet<T, N> &x, const Jet<T, N> &y) {
  return x.s < y.s;
}
  
template<typename T, size_t N>
bool operator > (const Jet<T, N> &x, const Jet<T, N> &y) {
  return x.s > y.s;
}


  
template<typename T, size_t N>
Jet<T, N> operator - (const Jet<T, N> &x) {
  return { -x.s, -x.e };
}

  
template<typename T, size_t N>
Jet<T, N> sqrt(const Jet<T, N> &x) {
  const T ss = std::sqrt(x.s);
  return {
    ss,
    x.e / (static_cast<T>(2) * ss)
  };
}
  


}
