//
//  GamepadFilter.h
//  Artemis
//
//  Lets the remote desktop controls see each controller's state before ControllerSupport
//  sends it to the PC, so a controller can drive the mouse instead (GamepadMouse.swift).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ArtemisGamepadFilterResult) {
    /// Send the state to the PC as usual.
    ArtemisGamepadFilterResultSend,
    /// Keep it from the PC.
    ArtemisGamepadFilterResultWithhold,
    /// Send the controller at rest instead (nothing stays held on the PC), then keep the rest.
    ArtemisGamepadFilterResultSendNeutral,
};

@protocol ArtemisGamepadFilter <NSObject>

/// A controller's merged state (Moonlight's button flags, sticks from -32767 to 32767, up is
/// positive), before it's sent. Called with ControllerSupport's locks held, on the main thread
/// except for old MFi controllers' Start button: don't block, and don't call back into it.
- (ArtemisGamepadFilterResult) filterController:(NSInteger)index
                  buttons:(uint32_t)buttons
               leftStickX:(int16_t)leftStickX
               leftStickY:(int16_t)leftStickY
              rightStickX:(int16_t)rightStickX
              rightStickY:(int16_t)rightStickY;

- (void) controllerDisconnected:(NSInteger)index;

@end

NS_ASSUME_NONNULL_END
