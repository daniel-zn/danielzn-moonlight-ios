//
//  SceneDelegate.h
//  Moonlight
//
//  iOS 27 ends apps that don't use the scene lifecycle, so the iPhone app
//  loads its storyboard through a window scene.
//

#import <UIKit/UIKit.h>

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>

@property (strong, nonatomic) UIWindow *window;

@end
