// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.


#import <TargetConditionals.h>
#if !(TARGET_IPHONE_SIMULATOR)
#import <Metal/Metal.h>
#endif
#import "ARCalibrateView.h"

@implementation ARCalibrateView

/**
 For Metal compatibility.
 */
+ (Class)layerClass
{
#if !(TARGET_IPHONE_SIMULATOR)
  return [CAMetalLayer class];
#else
  return [super layerClass];
#endif
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

