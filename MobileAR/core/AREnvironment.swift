// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import Foundation
import CoreLocation

/// Number of levels to sample lights.
let kSamplingLevels: Int = 7


/**
 Environment load errors.
 */
enum AREnvironmentError : ErrorType {
  case MalformedData
  case MissingEnvironmentMap
  case MissingHDRMap
}


/**
 Class storing environment information & light sources.
 */
class AREnvironment {
  // Path where the environment is stored.
  let path: NSURL
  // Name of the environment, provided by user.
  var name: String!
  // GPS coordinate where the image was taken.
  var location: CLLocation?

  // Tone-Mapped environment map preview.
  var ldr: UIImage!
  // High Dynamic Range environment map.
  var hdr: ARHDRImage!
  // List of light sources.
  var lightsLDR: [ARLight] = []
  // List of light sources.
  var lightsHDR: [ARLight] = []
  // List of images.
  var images: [AREnvironmentMap] = []

  /**
   Creates a new environment.
   */
  init(
      path: NSURL,
      name: String,
      location: CLLocation?,
      images: [AREnvironmentMap])
  {
    self.path = path
    self.name = name
    self.location = location
    self.images = images
    self.hdr = ARHDRBuilder.build(self.images)
    self.ldr = ARToneMapper.map(self.hdr)
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
    self.ldr = UIImage(contentsOfFile: environmentPath)

    // Locate the HDR map.
    guard let hdrPath = path.URLByAppendingPathComponent("envmap.hdr").path else {
      throw AREnvironmentError.MissingHDRMap
    }
    guard NSFileManager.defaultManager().fileExistsAtPath(hdrPath) else {
      throw AREnvironmentError.MissingHDRMap
    }
    self.hdr = ARHDRImage(data: NSData(contentsOfFile: hdrPath)!)

    // Sample so we can adjust levels.
    self.lightsLDR = ARLightProbeSampler.sampleVarianceCutLDR(ldr, levels: kSamplingLevels)
    self.lightsHDR = ARLightProbeSampler.sampleVarianceCutHDR(hdr, levels: kSamplingLevels)
  }

  /**
   Saves the environment.
   */
  func save() throws {
    do {
      // Create the directory where the environment will be stored.
      try NSFileManager.defaultManager().createDirectoryAtURL(
          path,
          withIntermediateDirectories: true,
          attributes: nil
      )

      // Write the data to the json file.
      var data : [String : AnyObject] = [ "name": name ]

      // If position is available, save it.
      if let loc = location {
        data["location"] = [
            "lat": loc.coordinate.latitude,
            "lng": loc.coordinate.longitude,
            "alt": loc.altitude
        ]
      }

      // Save all images.
      var index = 0
      var imageData : [String: AnyObject] = [:]
      for image in images {
        imageData["\(index)"] = [
          "exposure": image.exposure,
          "image": "\(index)"
        ]

        // Write the exposure level.
        try UIImagePNGRepresentation(image.map)?.writeToURL(
          path.URLByAppendingPathComponent("exp_\(index).png"),
          options: NSDataWritingOptions()
        )

        index = index + 1
      }
      data["images"] = imageData

      // Write the HDR image.
      try hdr.data().writeToURL(
          path.URLByAppendingPathComponent("envmap.hdr"),
          options: NSDataWritingOptions()
      )

      // Write the tone-mapped envmap.
      try UIImagePNGRepresentation(ldr)?.writeToURL(
          path.URLByAppendingPathComponent("envmap.png"),
          options: NSDataWritingOptions()
      )

      // Write the JSON dict.
      (try NSJSONSerialization.dataWithJSONObject(
          data,
          options: NSJSONWritingOptions()
      )).writeToURL(
          path.URLByAppendingPathComponent("data.json"),
          atomically: true
      )
    } catch {
      try NSFileManager.defaultManager().removeItemAtURL(path)
      throw error
    }
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
    { (url, err) in
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
