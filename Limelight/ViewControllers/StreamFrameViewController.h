//
//  StreamFrameViewController.h
//  Moonlight
//
//  Created by Diego Waxemberg on 1/18/14.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "Connection.h"
#import "StreamConfiguration.h"
#import "StreamView.h"

#import <UIKit/UIKit.h>

#if TARGET_OS_TV
@import GameController;

@interface StreamFrameViewController : GCEventViewController <ConnectionCallbacks, ControllerSupportDelegate, UserInteractionDelegate, UIScrollViewDelegate>
#else
@interface StreamFrameViewController : UIViewController <ConnectionCallbacks, ControllerSupportDelegate, UserInteractionDelegate, UIScrollViewDelegate>
#endif
@property (nonatomic) StreamConfiguration* streamConfig;
/// Called once the stream has ended and the view has been dismissed.
/// Called once the stream view is gone; `connected`: the session got as far as connecting.
@property (nonatomic, copy) void (^onExit)(BOOL connected);

-(void)updatePreferredDisplayMode:(BOOL)streamActive;

@end
