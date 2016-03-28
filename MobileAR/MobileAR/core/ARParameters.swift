// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import Foundation

enum ARParametersError: ErrorType {
  case MissingKey
  case InvalidType
}

@objc class ARParameters : NSObject {
  // Focal distance & principal point.
  let fx: Float
  let fy: Float
  let cx: Float
  let cy: Float

  // Distortion.
  let k1: Float
  let k2: Float
  let r1: Float
  let r2: Float

  // Camera focal distance [0.0, 1.0f]
  let f: Float

  @objc required init(
    fx: Float,
    fy: Float,
    cx: Float,
    cy: Float,
    k1: Float,
    k2: Float,
    r1: Float,
    r2: Float,
    f: Float)
  {
    self.fx = fx
    self.fy = fy
    self.cx = cx
    self.cy = cy
    self.k1 = k1
    self.k2 = k2
    self.r1 = r1
    self.r2 = r2
    self.f = f
  }

  /**
   Loads the calibration parameters from a file.
   */
  @objc static func loadFromFile() throws -> ARParameters {

    let data = try NSData(contentsOfURL: getParametersFileURL(), options: NSDataReadingOptions())
    let json = try NSJSONSerialization.JSONObjectWithData(
        data,
        options: NSJSONReadingOptions()
    ) as! [String: AnyObject]

    let fetch: (String) throws -> Float = { (key) throws in
      guard let val = json[key] as? Float else {
        throw ARParametersError.MissingKey
      }
      return val
    }

    return ARParameters(
        fx: try fetch("fx"),
        fy: try fetch("fy"),
        cx: try fetch("cx"),
        cy: try fetch("cy"),
        k1: try fetch("k1"),
        k2: try fetch("k2"),
        r1: try fetch("r1"),
        r2: try fetch("r2"),
        f:  try fetch("f")
    )
  }

  /**
   Saves the calibration file.
   */
  static func saveToFile(params: ARParameters) {
    (try! NSJSONSerialization.dataWithJSONObject([
          "fx": params.fx,
          "fy": params.fy,
          "cx": params.cx,
          "cy": params.cy,
          "k1": params.k1,
          "k2": params.k2,
          "r1": params.r1,
          "r2": params.r2,
          "f":  params.f
        ],
        options: NSJSONWritingOptions()
    )).writeToURL(getParametersFileURL(), atomically: true)
  }

  /**
   Returns the URL to the file storing the parameters.
   */
  static func getParametersFileURL() -> NSURL {
    return NSFileManager.defaultManager().URLsForDirectory(
        .DocumentDirectory,
        inDomains: .UserDomainMask
    )[0].URLByAppendingPathComponent("params.json")
  }
}
