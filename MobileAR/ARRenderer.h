// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

#import <UIKit/UIKit.h>

@interface ARRenderer : NSObject

- (id)initWithView:(UIView*)uiView;
- (void)render;
- (void)start;
- (void)stop;

@end
