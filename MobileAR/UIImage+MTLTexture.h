// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>


/**
 Extends an image to convert it to MTLTexture.
 */
@interface UIImage (MTLTexture)

-(void) toMTLTexture:(id<MTLTexture>)texture;

@end