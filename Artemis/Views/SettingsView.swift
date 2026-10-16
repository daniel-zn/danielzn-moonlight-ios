//
//  SettingsView.swift
//  Artemis
//
//  Settings in the Mac app's sections and wording, as an iOS settings list.
//  Every change is saved as it's made.
//

import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case video = "Video & Display"
    case audio = "Audio & Microphone"
    case keyboard = "Keyboard & Mouse"
    case controllers = "Game Controllers"
    case touch = "Touch Controls"
    case host = "Host PC"
    case general = "General"
    case advanced = "Advanced"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .video: "display"
        case .audio: "speaker.wave.2.fill"
        case .keyboard: "keyboard.fill"
        case .controllers: "gamecontroller.fill"
        case .touch: "hand.tap.fill"
        case .host: "desktopcomputer"
        case .general: "gearshape.fill"
        case .advanced: "wrench.and.screwdriver.fill"
        }
    }

    var color: Color {
        switch self {
        case .video: .blue
        case .audio: .pink
        case .keyboard: .teal
        case .controllers: .green
        case .touch: .orange
        case .host: .indigo
        case .general: .gray
        case .advanced: .gray
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = StreamSettings.load()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(SettingsSection.allCases) { section in
                        NavigationLink(value: section) {
                            Label {
                                Text(section.rawValue)
                            } icon: {
                                SettingsIcon(symbol: section.symbol, color: section.color)
                            }
                        }
                        .accessibilityIdentifier("settings.\(section)")
                    }
                } footer: {
                    Text("Streaming as \(settings.resolutionSummary) at \(settings.framerate) FPS, \(settings.bitrateText).")
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsSection.self) { section in
                SettingsPage(section: section, settings: $settings)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
        .onChange(of: settings) { _, new in
            new.save()
        }
    }
}

/// The colored rounded-square icons of the iOS Settings app.
struct SettingsIcon: View {
    let symbol: String
    let color: Color
    @ScaledMetric(relativeTo: .body) private var size = 29

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: .rect(cornerRadius: size * 0.24))
    }
}

struct SettingsPage: View {
    let section: SettingsSection
    @Binding var settings: StreamSettings
    @State private var resolutions = StreamSettings.presetResolutions
    @State private var customWidth = ""
    @State private var customHeight = ""
    @State private var askingCustomResolution = false
    @State private var customResolutionNote = false

    var body: some View {
        Form {
            switch section {
            case .video: video
            case .audio: audio
            case .keyboard: keyboard
            case .controllers: controllers
            case .touch: touch
            case .host: host
            case .general: general
            case .advanced: advanced
            }
        }
        .navigationTitle(section.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Video & Display

    private var resolutionChoice: Binding<String> {
        Binding(
            get: {
                resolutions.first { $0.width == settings.width && $0.height == settings.height }?.id ?? "custom"
            },
            set: { id in
                if id == "custom" {
                    customWidth = String(settings.width)
                    customHeight = String(settings.height)
                    askingCustomResolution = true
                } else if let choice = resolutions.first(where: { $0.id == id }) {
                    settings.width = choice.width
                    settings.height = choice.height
                    settings.resetBitrate()
                }
            })
    }

    @ViewBuilder
    private var video: some View {
        Section {
            Picker("Resolution", selection: resolutionChoice) {
                ForEach(resolutions) { resolution in
                    Text(resolution.name).tag(resolution.id)
                        .selectionDisabled(!resolution.isEnabled)
                }
                Text(isCustom ? "Custom (\(settings.width) × \(settings.height))" : "Custom…").tag("custom")
            }
            .accessibilityIdentifier("settings.resolution")
            Picker("Frame rate", selection: Binding(
                get: { settings.framerate },
                set: { settings.framerate = $0; settings.resetBitrate() }
            )) {
                Text("30 FPS").tag(30)
                Text("60 FPS").tag(60)
                if StreamSettings.supports120FPS || settings.framerate == 120 {
                    Text("120 FPS").tag(120)
                }
            }
            LabeledContent("Set PC/Game resolution", value: "\(settings.width) × \(settings.height)")
        } header: {
            Text("Resolution and FPS")
        } footer: {
            Text("Setting values too high for your PC or network connection may cause lag, stuttering, or errors.")
        }

        Section {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Video bitrate", value: settings.bitrateText)
                Slider(
                    value: Binding(
                        get: { Double(StreamSettings.notch(for: settings.bitrate)) },
                        set: { settings.bitrate = StreamSettings.bitrateTable[Int($0.rounded())] }
                    ),
                    in: 0...Double(StreamSettings.bitrateTable.count - 1),
                    step: 1
                ) {
                    Text("Video bitrate")
                } minimumValueLabel: {
                    Image(systemName: "tortoise")
                } maximumValueLabel: {
                    Image(systemName: "hare")
                }
                .accessibilityValue(settings.bitrateText)
                .accessibilityIdentifier("settings.bitrate")
            }
        } footer: {
            Text("Lower the bitrate on slower connections. Raise the bitrate to increase image quality.")
        }

        Section {
            Toggle("Enable HDR", isOn: $settings.enableHdr)
                .disabled(!ArtemisBridge.isHdrSupported())
        } footer: {
            Text(ArtemisBridge.isHdrSupported()
                 ? "The stream will be HDR-capable, but some games may require an HDR monitor on your host PC to enable HDR mode."
                 : "HDR streaming is not supported on this iPhone.")
        }

        Section {
            Toggle("Frame pacing", isOn: $settings.useFramePacing)
        } footer: {
            Text("Frame pacing reduces micro-stutter by delaying frames that come in too early, for the smoothest video at the cost of a little latency.")
        }

        Section {
            Toggle("Show performance stats while streaming", isOn: $settings.statsOverlay)
        } footer: {
            Text("Display real-time stream performance information while streaming.")
        }
        .alert("Enter a custom resolution:", isPresented: $askingCustomResolution) {
            TextField("Video width", text: $customWidth)
                .keyboardType(.numberPad)
            TextField("Video height", text: $customHeight)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("OK") { applyCustomResolution() }
        }
        .alert("Custom Resolution Selected", isPresented: $customResolutionNote) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Custom resolutions are not officially supported by GeForce Experience, so it will not set your host display resolution. You will need to set it manually while in game.\n\nResolutions that are not supported by your client or host PC may cause streaming errors.")
        }
    }

    private var isCustom: Bool {
        !resolutions.contains { $0.width == settings.width && $0.height == settings.height }
    }

    private func applyCustomResolution() {
        guard let width = Int(customWidth), let height = Int(customHeight), width > 0, height > 0 else { return }
        // Cap to the decoder's maximum and a sensible minimum
        let maximum = StreamSettings.maxResolutionDimension
        settings.width = max(256, min(width, maximum))
        settings.height = max(256, min(height, maximum))
        settings.resetBitrate()
        customResolutionNote = true
    }

    // MARK: Other sections

    @ViewBuilder
    private var audio: some View {
        Section {
            Toggle("Mute host PC speakers while streaming", isOn: Binding(
                get: { !settings.playAudioOnPC },
                set: { settings.playAudioOnPC = !$0 }
            ))
        } header: {
            Text("Audio Settings")
        } footer: {
            Text("Game audio plays on this iPhone. Turn this off to hear it on the PC too.")
        }
    }

    @ViewBuilder
    private var keyboard: some View {
        Section {
            Toggle("Citrix X1 mouse support", isOn: $settings.btMouseSupport)
        } footer: {
            Text("Use a Citrix X1 Bluetooth mouse while streaming. Other mice and keyboards work without this.")
        }
    }

    @ViewBuilder
    private var controllers: some View {
        Section {
            Toggle("Multiple controllers", isOn: $settings.multiController)
        } header: {
            Text("Gamepad Settings")
        } footer: {
            Text("On: each connected controller is its own player. Off: every controller controls player 1.")
        }
        Section {
            Toggle("Swap A/B and X/Y gamepad buttons", isOn: $settings.swapABXYButtons)
        } footer: {
            Text("This switches gamepads into a Nintendo-style button layout.")
        }
    }

    @ViewBuilder
    private var touch: some View {
        Section {
            Toggle("Use touchscreen as a virtual trackpad", isOn: Binding(
                get: { !settings.absoluteTouchMode },
                set: { settings.absoluteTouchMode = !$0 }
            ))
        } footer: {
            Text("When on, the touchscreen acts like a trackpad. When off, it directly controls the mouse pointer, and you can pinch to zoom the stream.")
        }
        Section {
            Picker("On-screen controls", selection: $settings.onscreenControls) {
                Text("Off").tag(0)
                Text("Automatic").tag(1)
                Text("Simple").tag(2)
                Text("Full").tag(3)
            }
            .disabled(settings.absoluteTouchMode)
        } footer: {
            Text(settings.absoluteTouchMode
                 ? "On-screen controls are off while the touchscreen controls the pointer directly."
                 : "Automatic shows them when no controller is connected.")
        }
    }

    @ViewBuilder
    private var host: some View {
        Section {
            Toggle("Optimize game settings for streaming", isOn: $settings.optimizeGames)
        } header: {
            Text("Host Settings")
        } footer: {
            Text("Lets the host change a game's settings to suit the stream.")
        }
    }

    @ViewBuilder
    private var general: some View {
        Section("About") {
            LabeledContent("Version", value: Self.version)
        }
        Section {
            Link(destination: Links.setupGuide) {
                Label("Setup Guide", systemImage: "book")
            }
            Link(destination: Links.troubleshooting) {
                Label("Troubleshooting", systemImage: "questionmark.circle")
            }
        } header: {
            Text("Help")
        } footer: {
            Text("Artemis is based on Moonlight, an open-source client for Sunshine and Apollo.")
        }
    }

    @ViewBuilder
    private var advanced: some View {
        Section {
            Picker("Video codec", selection: $settings.codec) {
                Text("Automatic (Recommended)").tag(0)
                Text("H.264").tag(1)
                if ArtemisBridge.isHevcSupported() || settings.codec == 2 {
                    Text("HEVC (H.265)").tag(2)
                }
                if ArtemisBridge.isAv1Supported() || settings.codec == 3 {
                    Text("AV1").tag(3)
                }
            }
        } header: {
            Text("Advanced Settings")
        } footer: {
            Text("Automatic picks the most efficient codec this iPhone decodes in hardware.")
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

extension StreamSettings {
    var resolutionSummary: String {
        StreamSettings.presetResolutions.first { $0.width == width && $0.height == height }?.name ?? "\(width) × \(height)"
    }
}
