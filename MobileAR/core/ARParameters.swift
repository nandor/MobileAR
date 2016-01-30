// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import Foundation

@objc class ARParameters : NSObject {
  let fx: Float
  let fy: Float
  let cx: Float
  let cy: Float
  let k1: Float
  let k2: Float
  let r1: Float
  let r2: Float

  @objc required init(
    fx : Float,
    fy : Float,
    cx : Float,
    cy : Float,
    k1 : Float,
    k2 : Float,
    r1 : Float,
    r2 : Float)
  {
    self.fx = fx
    self.fy = fy
    self.cx = cx
    self.cy = cy
    self.k1 = k1
    self.k2 = k2
    self.r1 = r1
    self.r2 = r2
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

    return ARParameters(
        fx: json["fx"] as! Float,
        fy: json["fy"] as! Float,
        cx: json["cx"] as! Float,
        cy: json["cy"] as! Float,
        k1: json["k1"] as! Float,
        k2: json["k2"] as! Float,
        r1: json["r1"] as! Float,
        r2: json["r2"] as! Float
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
          "r2": params.r2
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
