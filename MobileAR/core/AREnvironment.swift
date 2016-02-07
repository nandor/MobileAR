// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import Foundation
import CoreLocation

enum AREnvironmentError : ErrorType {
  case MalformedData
  case MissingEnvironmentMap
}

class AREnvironment {
  let path: NSURL

  // Name of the environment, provided by user.
  var name: String!

  // Environment map.
  var map: UIImage!

  // GPS coordinate where the image was taken.
  var location: CLLocation?

  /**
   Creates a new environment.
   */
  init(
      path: NSURL,
      name: String,
      location: CLLocation?)
  {
    self.path = path
    self.name = name
    self.location = location
  }

  /**
   Creates a new environment by reading its data from a directory.
   */
  init(path: NSURL) throws {
    self.path = path

    // Load the metadata.
    let data = try NSData(
        contentsOfURL: path.URLByAppendingPathComponent("data.json"),
        options: NSDataReadingOptions()
    )
    let meta = try NSJSONSerialization.JSONObjectWithData(
        data,
        options: NSJSONReadingOptions()
    ) as! [String: AnyObject]

    // Unwrap the name.
    guard let name = meta["name"] as? String else {
      throw AREnvironmentError.MalformedData
    }
    self.name = name

    // Unwrap the location if it exists.
    if let loc = meta["location"] as? [String : AnyObject] {
      guard let lat = loc["lat"] as? Double else { throw AREnvironmentError.MalformedData }
      guard let lng = loc["lng"] as? Double else { throw AREnvironmentError.MalformedData }
      guard let alt = loc["alt"] as? Double else { throw AREnvironmentError.MalformedData }

      self.location = CLLocation(
          coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
          altitude: alt,
          horizontalAccuracy: 0,
          verticalAccuracy: 0,
          timestamp: NSDate()
      )
    }

    // Load the environment map.
    guard let environmentPath = path.URLByAppendingPathComponent("envmap.png").path else {
      throw AREnvironmentError.MissingEnvironmentMap
    }
    guard NSFileManager.defaultManager().fileExistsAtPath(environmentPath) else {
      throw AREnvironmentError.MissingEnvironmentMap
    }
    self.map = UIImage(contentsOfFile: environmentPath)
  }

  /**
   Saves the environment.
   */
  func save() {

    // Create the directory where the environment will be stored.
    try! NSFileManager.defaultManager().createDirectoryAtURL(
        path,
        withIntermediateDirectories: true,
        attributes: nil
    )

    // Write the data to the json file.
    var data : [String : AnyObject ] = [ "name": name ]
    if let loc = location {
      data["location"] = [
          "lat": loc.coordinate.latitude,
          "lng": loc.coordinate.longitude,
          "alt": loc.altitude
      ]
    }
    (try! NSJSONSerialization.dataWithJSONObject(
        data,
        options: NSJSONWritingOptions()
    )).writeToURL(
        path.URLByAppendingPathComponent("data.json"),
        atomically: true
    )
  }

  /**
   Returns a list of all saved environments in the "Documents/Environment" folder.
   */
  static func all() -> [AREnvironment] {

    // Create an enumerator for the Environments directory.
    let enumerator = NSFileManager.defaultManager().enumeratorAtURL(
        getEnvironmentsDirectoryURL(),
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

  /**
   Returns the directory storing the environments.
   */
  static func getEnvironmentsDirectoryURL() -> NSURL {
    return NSFileManager.defaultManager().URLsForDirectory(
        .DocumentDirectory,
        inDomains: .UserDomainMask
    )[0].URLByAppendingPathComponent("Environments")
  }
}
