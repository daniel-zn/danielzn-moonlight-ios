//
//  SceneDelegate.swift
//  Artemis
//
//  Hosts the SwiftUI app in the window, presents the stream view from it and
//  forwards home-screen quick actions. Apps built with the iOS 27 SDK must use scenes.
//

import SwiftUI
import UIKit

@objc(SceneDelegate)
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let store = ComputerStore(demo: DemoData.isEnabled)

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let hosting = UIHostingController(rootView: RootView().environment(store))
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        self.window = window
        // Code from before scenes looks for the window on the app delegate
        (UIApplication.shared.delegate as? AppDelegate)?.window = window

        store.presentStream = { [weak hosting] config, onExit in
            guard let hosting else { return }
            let stream = ArtemisBridge.streamViewController(with: config, onExit: onExit)
            var presenter: UIViewController = hosting
            while let presented = presenter.presentedViewController {
                presenter = presented
            }
            presenter.present(stream, animated: true)
        }
        store.start()

        if let shortcut = connectionOptions.shortcutItem {
            store.handleShortcut(shortcut)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(store.handleShortcut(shortcutItem))
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        (UIApplication.shared.delegate as? AppDelegate)?.saveContext()
    }
}
