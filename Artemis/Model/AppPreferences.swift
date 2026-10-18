//
//  AppPreferences.swift
//  Artemis
//
//  Settings the Mac app has that upstream's database doesn't, saved in UserDefaults (the
//  settings screen binds them with @AppStorage under the same keys).
//

import Foundation

enum AppPreferences {
    enum Keys {
        /// Host PC › End the app on the PC after a session.
        static let quitAppAfterSession = "ArtemisQuitAppAfterSession"
        /// Controllers › Mouse control with a controller (hold Start / Menu).
        static let gamepadMouse = "ArtemisGamepadMouse"
        /// Keyboard & Mouse › Swap left and right mouse buttons (a connected mouse; read by ControllerSupport).
        static let swapMouseButtons = "ArtemisSwapMouseButtons"
    }

    static var quitAppAfterSession: Bool {
        UserDefaults.standard.bool(forKey: Keys.quitAppAfterSession)
    }

    static var gamepadMouse: Bool {
        // bool(forKey:) also reads "YES" / "NO" from launch arguments
        UserDefaults.standard.object(forKey: Keys.gamepadMouse) == nil || UserDefaults.standard.bool(forKey: Keys.gamepadMouse)
    }
}
