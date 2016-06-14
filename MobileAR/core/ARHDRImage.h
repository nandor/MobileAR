// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <Foundation/Foundation.h>


/**
 Matrix storing HDR, floating point images.
 
 At this point, it is basically a serializable floating-point buffer.
 */
@interface ARHDRImage : NSObject

@property (nonatomic) int width;
@property (nonatomic) int height;
@property (nonatomic) size_t stride;

/**
 Creates a matrix, assuming no padding at the end of rows.
 */
- (instancetype)initWithMatrix:(const float*)data width:(int)width height:(int)height;

/**
 Creates a matrix with fixed stride.
 */
- (instancetype)initWithMatrix:(const float*)data width:(int)width height:(int)height stride:(size_t)stride;

/**
 Creates the image from NSData.
 */
- (instancetype)initWithData:(NSData*)data;

/**
 Returns the image as NSData, to be written to disk.
 */
- (NSData*)data;

/**
 Returns the raw contents of the image.
 */
- (const float*)matrix;

@end
