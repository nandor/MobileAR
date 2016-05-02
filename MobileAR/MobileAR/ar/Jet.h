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
  
  inline Jet<T, N> operator += (const Jet<T, N> &y) {
    *this = *this + y;
    return *this;
  }

  // Scalar part.
  T s;
  // Vector part.
  Eigen::Matrix<T, N, 1> e;
};

  
template<typename T, size_t N>
inline Jet<T, N> operator * (const Jet<T, N> &x, const Jet<T, N> &y) {
  return { x.s * y.s, x.s * y.e + y.s * x.e };
}
  

template<typename T, size_t N>
inline Jet<T, N> operator / (const Jet<T, N> &x, const Jet<T, N> &y) {
  const T s = x.s / y.s;
  return {
    s,
    (x.e - y.e * s) / y.s
  };
}

  
template<typename T, size_t N>
inline Jet<T, N> operator + (const Jet<T, N> &x, const Jet<T, N> &y) {
  return { x.s + y.s, x.e + y.e };
}

  
template<typename T, size_t N>
inline Jet<T, N> operator - (const Jet<T, N> &x, const Jet<T, N> &y) {
  return { x.s - y.s, x.e - y.e };
}
  
  
template<typename T, size_t N>
inline bool operator < (const Jet<T, N> &x, const Jet<T, N> &y) {
  return x.s < y.s;
}
  
template<typename T, size_t N>
inline bool operator > (const Jet<T, N> &x, const Jet<T, N> &y) {
  return x.s > y.s;
}

template<typename T, size_t N>
inline Jet<T, N> operator * (const Jet<T, N> &x, const T &s) {
  return { x.s * s, x.e * s };
}
  
template<typename T, size_t N>
inline Jet<T, N> operator * (const T &s, const Jet<T, N> &x) {
  return { x.s * s, x.e * s };
}


  
template<typename T, size_t N>
inline Jet<T, N> operator - (const Jet<T, N> &x) {
  return { -x.s, -x.e };
}

  
template<typename T, size_t N>
inline Jet<T, N> sqrt(const Jet<T, N> &x) {
  const T ss = std::sqrt(x.s);
  return {
    ss,
    x.e / (static_cast<T>(2) * ss)
  };
}
  
template<typename T, size_t N>
inline Jet<T, N> sin(const Jet<T, N> &x) {
  return {
    std::sin(x.s),
    std::cos(x.s) * x.e
  };
}

template<typename T, size_t N>
inline Jet<T, N> cos(const Jet<T, N> &x) {
  return {
    std::cos(x.s),
    -std::sin(x.s) * x.e
  };
}

}
