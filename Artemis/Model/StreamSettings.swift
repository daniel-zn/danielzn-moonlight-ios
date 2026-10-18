//
//  StreamSettings.swift
//  Artemis
//
//  The saved streaming settings (the Core Data Settings entity, through DataManager),
//  with the old settings screen's rules: the bitrate notches, the default bitrate for a
//  resolution and frame rate, the resolutions this device offers.
//

import UIKit

struct StreamSettings: Equatable {
    var width: Int
    var height: Int
    var framerate: Int
    /// Kbps.
    var bitrate: Int
    /// 0 automatic, 1 H.264, 2 HEVC, 3 AV1 (TemporarySettings' CODEC_PREF_*).
    var codec: Int
    var enableHdr: Bool
    var useFramePacing: Bool
    var statsOverlay: Bool
    var playAudioOnPC: Bool
    var optimizeGames: Bool
    var multiController: Bool
    var swapABXYButtons: Bool
    var btMouseSupport: Bool
    var absoluteTouchMode: Bool
    /// OnScreenControlsLevel: off, auto, simple, full.
    var onscreenControls: Int

    static func load() -> StreamSettings {
        let saved = DataManager().getSettings()!
        var settings = StreamSettings(
            width: saved.width?.intValue ?? 1280,
            height: saved.height?.intValue ?? 720,
            framerate: saved.framerate?.intValue ?? 60,
            bitrate: saved.bitrate?.intValue ?? 10000,
            codec: Int(ArtemisBridge.codecPreference(of: saved)),
            enableHdr: saved.enableHdr,
            useFramePacing: saved.useFramePacing,
            statsOverlay: saved.statsOverlay,
            playAudioOnPC: saved.playAudioOnPC,
            optimizeGames: saved.optimizeGames,
            multiController: saved.multiController,
            swapABXYButtons: saved.swapABXYButtons,
            btMouseSupport: saved.btMouseSupport,
            absoluteTouchMode: saved.absoluteTouchMode,
            onscreenControls: saved.onscreenControls?.intValue ?? 1)
        // Ensure we pick a bitrate that falls exactly onto a slider notch
        settings.bitrate = Self.bitrateTable[Self.notch(for: settings.bitrate)]
        return settings
    }

    func save() {
        DataManager().saveSettings(
            withBitrate: bitrate,
            framerate: framerate,
            height: height,
            width: width,
            audioConfig: 2, // Stereo
            onscreenControls: onscreenControls,
            optimizeGames: optimizeGames,
            multiController: multiController,
            swapABXYButtons: swapABXYButtons,
            audioOnPC: playAudioOnPC,
            preferredCodec: UInt32(codec),
            useFramePacing: useFramePacing,
            enableHdr: enableHdr,
            btMouseSupport: btMouseSupport,
            absoluteTouchMode: absoluteTouchMode,
            statsOverlay: statsOverlay)
    }

    // MARK: The default resolution

    /// Sessions default to this iPhone's own resolution ("Native": its screen's pixels in
    /// landscape) at its display's highest frame rate, so the host's virtual display matches the
    /// phone. Settings still at upstream's default (1280 × 720) move to it once; a resolution
    /// chosen later stays. Needs the window scene, so the store calls it at start.
    static func adoptNativeDefaultIfUnchanged() {
        let defaults = UserDefaults.standard
        // Demo only: start from upstream's default, to test the move
        if DemoData.isEnabled && defaults.bool(forKey: "ArtemisTestOldDefaultResolution") {
            var old = load()
            old.width = 1280
            old.height = 720
            old.framerate = 60
            old.save()
            defaults.removeObject(forKey: Keys.nativeDefaultApplied)
        }
        guard !defaults.bool(forKey: Keys.nativeDefaultApplied) else { return }
        defaults.set(true, forKey: Keys.nativeDefaultApplied)
        var settings = load()
        guard settings.width == 1280 && settings.height == 720,
              let native = presetResolutions.first(where: { $0.name == "Native" }) else { return }
        settings.width = native.width
        settings.height = native.height
        if settings.framerate == 60 && supports120FPS {
            settings.framerate = 120
        }
        settings.resetBitrate()
        settings.save()
        logInfo("Default resolution: \(native.width) × \(native.height) at \(settings.framerate) FPS")
    }

    private enum Keys {
        static let nativeDefaultApplied = "ArtemisNativeDefaultApplied"
    }

    // MARK: Bitrate

    static let bitrateTable = [
        500, 1000, 1500, 2000, 2500, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000,
        12000, 15000, 18000, 20000, 30000, 40000, 50000, 60000, 70000, 80000, 100000, 120000, 150000,
    ]

    static func notch(for bitrate: Int) -> Int {
        bitrateTable.firstIndex { bitrate <= $0 } ?? bitrateTable.count - 1
    }

    var bitrateText: String {
        let mbps = Double(bitrate) / 1000
        return mbps.rounded() == mbps ? "\(Int(mbps)) Mbps" : String(format: "%.1f Mbps", mbps)
    }

    /// The default bitrate for the resolution and frame rate (from Moonlight Qt).
    mutating func resetBitrate() {
        let fps = Float(framerate)
        // Don't scale bitrate linearly beyond 60 FPS. It's definitely not a linear
        // bitrate increase for frame rate once we get to values that high.
        let frameRateFactor = (fps <= 60 ? fps : (sqrtf(fps / 60) * 60)) / 30
        let resTable: [(pixels: Int, factor: Float)] = [
            (640 * 360, 1), (854 * 480, 2), (1280 * 720, 5), (1920 * 1080, 10), (2560 * 1440, 20), (3840 * 2160, 40),
        ]
        let pixels = width * height
        var resolutionFactor = resTable.last!.factor
        for (i, entry) in resTable.enumerated() {
            if pixels == entry.pixels {
                resolutionFactor = entry.factor
                break
            } else if pixels < entry.pixels {
                if i == 0 {
                    resolutionFactor = entry.factor
                } else {
                    // Interpolate between the entries around the chosen resolution
                    let lower = resTable[i - 1]
                    resolutionFactor = Float(pixels - lower.pixels) / Float(entry.pixels - lower.pixels) * (entry.factor - lower.factor) + lower.factor
                }
                break
            }
        }
        let defaultBitrate = Int((resolutionFactor * frameRateFactor).rounded()) * 1000
        bitrate = Self.bitrateTable[Self.notch(for: min(defaultBitrate, 100000))]
    }

    // MARK: Device capabilities

    private static var currentScreen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    static var supports120FPS: Bool {
        // Only show the 120 FPS option with a > 60-ish Hz display
        (currentScreen?.maximumFramesPerSecond ?? 60) > 62
    }

    struct Resolution: Identifiable, Hashable {
        var id: String { "\(width)x\(height)" }
        let name: String
        let width: Int
        let height: Int
        var isEnabled = true
    }

    /// 360p to 4K, and this phone's own screen with and without the notch area, in landscape.
    static var presetResolutions: [Resolution] {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let bounds = scene?.screen.bounds ?? CGRect(x: 0, y: 0, width: 402, height: 874)
        let scale = scene?.screen.scale ?? 3
        let long = max(bounds.width, bounds.height)
        let short = min(bounds.width, bounds.height)
        // In landscape the notch's inset is on both sides; upright it's the top inset.
        let window = scene?.keyWindow
        let insets = window?.safeAreaInsets ?? .zero
        let landscape = (window?.bounds.width ?? 0) > (window?.bounds.height ?? 0)
        let notchInset = landscape ? max(insets.left, insets.right) : insets.top
        let safeWidth = Int((long - notchInset * 2) * scale)
        let fullWidth = Int(long * scale), fullHeight = Int(short * scale)
        return [
            Resolution(name: "360p", width: 640, height: 360),
            Resolution(name: "720p", width: 1280, height: 720),
            Resolution(name: "1080p", width: 1920, height: 1080),
            // Only offer 4K on devices that decode HEVC
            Resolution(name: "4K", width: 3840, height: 2160, isEnabled: ArtemisBridge.isHevcSupported()),
            Resolution(name: "Native (Excluding Notch)", width: safeWidth, height: fullHeight),
            Resolution(name: "Native", width: fullWidth, height: fullHeight),
        ]
    }

    /// H.264's maximum, or HEVC's.
    static var maxResolutionDimension: Int {
        ArtemisBridge.isHevcSupported() ? 8192 : 4096
    }
}
