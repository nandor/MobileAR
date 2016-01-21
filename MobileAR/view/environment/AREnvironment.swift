// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import Foundation
import CoreLocation

enum AREnvironmentError : ErrorType {
  case MalformedData
}

class AREnvironment {
  let path: NSURL

  // Name of the environment, provided by user.
  var name: String!

  // GPS coordinate where the image was taken.
  var location: CLLocation!

  /**
   Creates a new environment by reading its data from a directory.
   */
  required init(path: NSURL) throws {
    self.path = path

    // Load the metadata.
    let data = try NSData(
        contentsOfURL: path.URLByAppendingPathComponent("data.json"),
        options: NSDataReadingOptions()
    )
    let meta = try NSJSONSerialization.JSONObjectWithData(
        data,
        options: NSJSONReadingOptions())

    // Unwrap the name.
    guard let name = meta["name"] as? String else { throw AREnvironmentError.MalformedData }
    self.name = name

    // Unwrap the location.
    guard let loc = meta["location"] as? [String:AnyObject] else {
      throw AREnvironmentError.MalformedData
    }
    guard let lat = loc["lat"] as? Double else { throw AREnvironmentError.MalformedData }
    guard let lng = loc["lng"] as? Double else { throw AREnvironmentError.MalformedData }
    guard let altitude = loc["altitude"] as? Double else { throw AREnvironmentError.MalformedData }
    guard let accVert = loc["accVert"] as? Double else { throw AREnvironmentError.MalformedData }
    guard let accHorz = loc["accHorz"] as? Double else { throw AREnvironmentError.MalformedData }
    self.location = CLLocation(
        coordinate: CLLocationCoordinate2D(latitude:lat, longitude: lng),
        altitude: altitude,
        horizontalAccuracy: accHorz,
        verticalAccuracy: accVert,
        timestamp: NSDate()
    )
  }

  /**
   Returns a list of all saved environments in the "Documents/Environment" folder.
   */
  static func all() -> [AREnvironment] {

    let fileManager = NSFileManager.defaultManager()

    // Create an enumerator for the Environments directory.
    let documents = fileManager.URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)[0]
    let enumerator = fileManager.enumeratorAtURL(
        documents.URLByAppendingPathComponent("Environments"),
        includingPropertiesForKeys: [ NSURLIsDirectoryKey ],
        options: .SkipsSubdirectoryDescendants)
    { (NSURL url, NSError err) in
      return false
    }

    // Find all directories and read environments from them.
    var environments : [AREnvironment] = [];
    while let url = enumerator?.nextObject() as? NSURL {
      do {
        var isDirectory: AnyObject?
        try url.getResourceValue(&isDirectory, forKey: NSURLIsDirectoryKey)
        if (isDirectory as? Bool) ?? false {
          if let environment = try? AREnvironment(path: url) {
            environments.append(environment)
          }
        }
      } catch {
      }
    }
    return environments;
  }
}
