// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import Foundation


/**
 Reads a file line by line.
 */
class ARFileReader {
  
  // File handle & temp buffer.
  let fileHandle: NSFileHandle!
  let delimiter: NSData!
  let buffer: NSMutableData!
  
  // Flag to indicate if there is data to be read.
  var eof = false
  
  /**
   Opens the file.
   */
  init(url: NSURL) throws {
    delimiter = "\n".dataUsingEncoding(NSUTF8StringEncoding)
    buffer = NSMutableData(capacity: 8192)
    
    do {
      fileHandle = try NSFileHandle(forReadingFromURL: url)
    } catch {
      fileHandle = nil
      throw error
    }
  }
  
  /**
   Closes the file.
   */
  deinit {
    fileHandle.closeFile()
    eof = true
  }
  
  /**
   Reads a line from the string.
   */
  func nextLine() -> String? {
    if eof {
      return nil
    }
    
    // Read chunks from the file until a newline is encountered.
    var range = buffer.rangeOfData(
        delimiter,
        options: [],
        range: NSMakeRange(0, buffer.length)
    )
    while range.location == NSNotFound {
      let chunk = fileHandle.readDataOfLength(8192)
      if chunk.length == 0 {
        eof = true
        
        if buffer.length <= 0 {
          return nil
        } else {
          return NSString(
              data: buffer,
              encoding: NSUTF8StringEncoding
          ) as String?
        }
      }
      
      buffer.appendData(chunk)
      range = buffer.rangeOfData(
          delimiter,
          options: [],
          range: NSMakeRange(0, buffer.length)
      )
    }
    
    // Extract data until the newline is found.
    let line = NSString(
        data: buffer.subdataWithRange(NSMakeRange(0, range.location)),
        encoding: NSUTF8StringEncoding
    )
    buffer.replaceBytesInRange(
        NSMakeRange(0, range.location + range.length),
        withBytes: nil,
       length: 0
    )
    return line as String?
  }
}

extension ARFileReader : SequenceType {
  func generate() -> AnyGenerator<String> {
    return AnyGenerator {
      return self.nextLine()
    }
  }
}

