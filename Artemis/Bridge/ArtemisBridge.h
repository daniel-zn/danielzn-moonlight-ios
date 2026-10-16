//
//  ArtemisBridge.h
//  Artemis
//
//  The blocking host operations the old MainFrameViewController ran on GCD
//  workers, for the SwiftUI model. Call them off the main thread.
//

#import <UIKit/UIKit.h>
#import "TemporaryHost.h"
#import "TemporaryApp.h"
#import "DiscoveryManager.h"
#import "StreamConfiguration.h"
#import "TemporarySettings.h"

NS_ASSUME_NONNULL_BEGIN

@interface ArtemisBridge : NSObject

/// Fetches serverinfo and updates the host with it. Returns nil on success,
/// otherwise the error message.
+ (nullable NSString*) refreshServerInfoForHost:(TemporaryHost*)host discovery:(nullable DiscoveryManager*)discovery;

/// Fetches the app list and merges it into the host and the database. Returns
/// nil on success, otherwise the error message.
+ (nullable NSString*) refreshAppListForHost:(TemporaryHost*)host discovery:(nullable DiscoveryManager*)discovery;

/// Quits the running app. Returns YES when the host confirms it quit.
+ (BOOL) quitAppOnHost:(TemporaryHost*)host discovery:(nullable DiscoveryManager*)discovery;

/// Saves an app's hidden flag.
+ (void) setApp:(TemporaryApp*)app hidden:(BOOL)hidden;

/// Runs the port test against the Moonlight test servers and describes the result.
+ (NSString*) runNetworkTest;

/// Appends a note to an add-PC error when this network blocks the streaming ports.
+ (NSString*) addHostErrorMessage:(NSString*)error;

/// The stream configuration for an app, from the saved settings and what this device supports.
+ (StreamConfiguration*) streamConfigurationForApp:(TemporaryApp*)app;

/// Fills in a saved host's address for this session.
+ (void) prepareSavedHost:(TemporaryHost*)host;

/// The saved codec preference: 0 automatic, 1 H.264, 2 HEVC, 3 AV1.
/// The stream view for a configuration, to present full screen. (StreamFrameViewController's
/// header can't go in the bridging header: it imports the generated Swift header.)
+ (UIViewController*) streamViewControllerWithConfiguration:(StreamConfiguration*)config onExit:(void (^)(void))onExit;

+ (int) codecPreferenceOfSettings:(TemporarySettings*)settings;

+ (BOOL) isHevcSupported;
+ (BOOL) isAv1Supported;
+ (BOOL) isHdrSupported;

@end

NS_ASSUME_NONNULL_END
