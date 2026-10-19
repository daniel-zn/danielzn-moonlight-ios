//
//  ControllerSupport.h
//  Moonlight
//
//  Created by Cameron Gutman on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "StreamConfiguration.h"
#import "Controller.h"
#import "GamepadFilter.h"

@class OnScreenControls;

@protocol ControllerSupportDelegate <NSObject>

- (void) gamepadPresenceChanged;
- (void) mousePresenceChanged;
- (void) streamExitRequested;

@end

/// Artemis: a gamepad state as sent to the PC.
typedef struct {
    uint32_t buttons;
    uint8_t leftTrigger, rightTrigger;
    int16_t leftStickX, leftStickY, rightStickX, rightStickY;
} ArtemisPadState;

@interface ControllerSupport : NSObject

/// Artemis: sees each controller's state first and can keep it from the PC (the gamepad mouse).
@property (nonatomic, weak) id<ArtemisGamepadFilter> gamepadFilter;

-(id) initWithConfig:(StreamConfiguration*)streamConfig delegate:(id<ControllerSupportDelegate>)delegate;
-(void) connectionEstablished;

-(void) initAutoOnScreenControlMode:(OnScreenControls*)osc;
-(void) cleanup;
-(Controller*) getOscController;

-(void) updateLeftStick:(Controller*)controller x:(short)x y:(short)y;
-(void) updateRightStick:(Controller*)controller x:(short)x y:(short)y;

-(void) updateLeftTrigger:(Controller*)controller left:(unsigned char)left;
-(void) updateRightTrigger:(Controller*)controller right:(unsigned char)right;
-(void) updateTriggers:(Controller*)controller left:(unsigned char)left right:(unsigned char)right;

-(void) updateButtonFlags:(Controller*)controller flags:(int)flags;
-(void) setButtonFlag:(Controller*)controller flags:(int)flags;
-(void) clearButtonFlag:(Controller*)controller flags:(int)flags;

-(void) updateFinished:(Controller*)controller;

-(void) rumble:(unsigned short)controllerNumber lowFreqMotor:(unsigned short)lowFreqMotor highFreqMotor:(unsigned short)highFreqMotor;
-(void) rumbleTriggers:(uint16_t)controllerNumber leftTrigger:(uint16_t)leftTrigger rightTrigger:(uint16_t)rightTrigger;
-(void) setMotionEventState:(uint16_t)controllerNumber motionType:(uint8_t)motionType reportRateHz:(uint16_t)reportRateHz;
-(void) setControllerLed:(uint16_t)controllerNumber r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b;

+(int) getConnectedGamepadMask:(StreamConfiguration*)streamConfig;

-(NSUInteger) getConnectedGamepadCount;

/// Artemis: the on-screen gamepad, an Xbox controller of its own (a player number no connected
/// controller has; player 1 without multiple controllers). Arrives with its first state.
-(void) connectVirtualGamepad;
-(void) sendVirtualGamepadButtons:(uint32_t)buttons leftTrigger:(uint8_t)leftTrigger rightTrigger:(uint8_t)rightTrigger
                       leftStickX:(int16_t)leftStickX leftStickY:(int16_t)leftStickY
                      rightStickX:(int16_t)rightStickX rightStickY:(int16_t)rightStickY;
/// At rest, then gone from the PC.
-(void) disconnectVirtualGamepad;

@end
