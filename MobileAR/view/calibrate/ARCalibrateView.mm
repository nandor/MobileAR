// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.


#import <TargetConditionals.h>

#if !(TARGET_IPHONE_SIMULATOR)

#import <Metal/Metal.h>
#import "ARCalibrateView.h"

@implementation ARCalibrateView

+ (Class)layerClass
{
  return [CAMetalLayer class];
}

@end

#else

#import "ARCalibrateView.h"

@implementation ARCalibrateView
@end

#endif
