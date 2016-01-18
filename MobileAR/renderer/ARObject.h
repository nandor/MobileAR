// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <Metal/Metal.h>


@interface ARObject : NSObject

- (id)initWithDevice:(id<MTLDevice>)device;
- (void)render:(MTLRenderPassDescriptor*)pass;

@end
