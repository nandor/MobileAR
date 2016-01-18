// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import Foundation

class AREnvironment {

  /**
   Creates a new environment by reading its data from a directory.
   */
  init?(path: NSURL) {
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
          if let environment = AREnvironment(path: url) {
            environments.append(environment)
          }
        }
      } catch {
      }
    }
    return environments;
  }
}
