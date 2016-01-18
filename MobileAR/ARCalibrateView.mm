// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <Metal/Metal.h>

#import "ARCalibrateView.h"

@implementation ARCalibrateView

/**
 For Metal compatibility.
 */
+ (Class)layerClass
{
  return [CAMetalLayer class];
}


/**
 Initializes the view.
 */
- (id)initWithFrame:(CGRect)frame
{
  if (!(self = [super initWithFrame:frame])) {
    return nil;
  }
  
  return self;
}

@end
