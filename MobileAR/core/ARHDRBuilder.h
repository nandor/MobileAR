// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <Foundation/Foundation.h>

#import "AREnvironmentBuilder.h"
#import "ARHDRImage.h"



@interface ARHDRBuilder : NSObject

+ (ARHDRImage*)build: (NSArray<AREnvironmentMap*>*) envmaps;

@end
