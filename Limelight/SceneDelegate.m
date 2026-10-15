//
//  SceneDelegate.m
//  Moonlight
//

#import "SceneDelegate.h"
#import "AppDelegate.h"

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    // The storyboard comes from the scene manifest; the app delegate keeps the
    // window too, as code written for the pre-scene lifecycle expects.
    AppDelegate* delegate = (AppDelegate*)[UIApplication sharedApplication].delegate;
    delegate.window = self.window;

    UIApplicationShortcutItem* shortcut = connectionOptions.shortcutItem;
    if (shortcut != nil) {
        delegate.pcUuidToLoad = (NSString*)[shortcut.userInfo objectForKey:@"UUID"];
    }
}

- (void)windowScene:(UIWindowScene *)windowScene performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL))completionHandler {
    AppDelegate* delegate = (AppDelegate*)[UIApplication sharedApplication].delegate;
    delegate.pcUuidToLoad = (NSString*)[shortcutItem.userInfo objectForKey:@"UUID"];
    delegate.shortcutCompletionHandler = completionHandler;
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    [(AppDelegate*)[UIApplication sharedApplication].delegate saveContext];
}

@end
