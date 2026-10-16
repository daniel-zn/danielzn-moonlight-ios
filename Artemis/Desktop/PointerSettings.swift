//
//  PointerSettings.swift
//  Artemis
//
//  Settings › Touch & Pointer that upstream's database doesn't have (the default mode is
//  its absoluteTouchMode). Saved in UserDefaults.
//

import Foundation

struct PointerSettings: Equatable {
    /// Scales the trackpad's pointer movement (0.5–2.5).
    var pointerSpeed: Double
    /// Content follows the fingers when scrolling, as on iOS.
    var naturalScrolling: Bool
    /// A session starts with the control bar open (otherwise folded into a button).
    var showControlBar: Bool

    static let speedRange = 0.5...2.5

    static func load() -> PointerSettings {
        let defaults = UserDefaults.standard
        return PointerSettings(
            pointerSpeed: defaults.object(forKey: Keys.speed) as? Double ?? 1.0,
            naturalScrolling: defaults.object(forKey: Keys.natural) as? Bool ?? true,
            showControlBar: defaults.object(forKey: Keys.showBar) as? Bool ?? true)
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(pointerSpeed, forKey: Keys.speed)
        defaults.set(naturalScrolling, forKey: Keys.natural)
        defaults.set(showControlBar, forKey: Keys.showBar)
    }

    private enum Keys {
        static let speed = "ArtemisPointerSpeed"
        static let natural = "ArtemisNaturalScrolling"
        static let showBar = "ArtemisShowControlBar"
    }
}
