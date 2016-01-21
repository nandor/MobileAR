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
  let k3: Float
  let r1: Float
  let r2: Float

  @objc required init(
    fx : Float,
    fy : Float,
    cx : Float,
    cy : Float,
    k1 : Float,
    k2 : Float,
    k3 : Float,
    r1 : Float,
    r2 : Float)
  {
    self.fx = fx
    self.fy = fy
    self.cx = cx
    self.cy = cy
    self.k1 = k1
    self.k2 = k2
    self.k3 = k3
    self.r1 = r1
    self.r2 = r2
  }

  static func loadFromFile() throws -> ARParameters {
    let fileManager = NSFileManager.defaultManager()
    let documents = fileManager.URLsForDirectory(
        .DocumentDirectory,
        inDomains: .UserDomainMask
    )[0]

    let data = try NSData(
        contentsOfURL: documents.URLByAppendingPathComponent("params.json"),
        options: NSDataReadingOptions()
    )
    let json = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions())

    return ARParameters(
        fx: json["fx"] as! Float,
        fy: json["fy"] as! Float,
        cx: json["cx"] as! Float,
        cy: json["cy"] as! Float,
        k1: json["k1"] as! Float,
        k2: json["k2"] as! Float,
        k3: json["k3"] as! Float,
        r1: json["r1"] as! Float,
        r2: json["r2"] as! Float
    )
  }

  static func saveToFile(params: ARParameters) {
  }
}
