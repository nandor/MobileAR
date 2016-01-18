// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import "ARObject.h"

@implementation ARObject

/**
 Initializes the object.
 */
- (id)initWithDevice:(id<MTLDevice>) device
{
  if (!(self = [super init])) {
    return nil;
  }
  return self;
}

/**
 Renders the object.
 */
- (void)render:(MTLRenderPassDescriptor*) pass
{
  
}

@end
