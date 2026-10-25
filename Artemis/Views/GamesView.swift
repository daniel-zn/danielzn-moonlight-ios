//
//  GamesView.swift
//  Artemis
//
//  A PC's apps, as rows with their artwork; an active app has a green dot after its name and
//  Resume and Stop under it, like the Mac app;
//  tapping connects to one or resumes the active session.
//

import SwiftUI

struct GamesView: View {
    let hostID: String
    @Environment(ComputerStore.self) private var store
    /// Opening another app while one is active: stop that one first?
    @State private var switching: Game?
    /// Stopping the active app.
    @State private var ending: Game?

    private var computer: Computer? { store.computer(hostID) }

    private var games: [Game] {
        store.games(for: hostID)
    }

    var body: some View {
        List {
            ForEach(games) { game in
                GameRow(game: game, onTap: { tapped(game) }, onResume: { store.play(game) }, onEnd: { ending = game })
                .contextMenu { menu(for: game) } preview: {
                    // The preview is drawn outside this view: it gets the store explicitly, or
                    // re-rendering it after a menu action finds no store in its environment
                    BoxArtView(game: game)
                        .frame(width: 240, height: 320)
                        .environment(store)
                }
                .swipeActions(edge: .trailing) {
                    if game.isRunning {
                        Button("Stop", systemImage: "stop.fill", role: .destructive) { ending = game }
                    } else if !game.isDirectLaunch || game.isHidden {
                        Button(game.isHidden ? "Show" : "Hide", systemImage: game.isHidden ? "eye" : "eye.slash") {
                            store.setHidden(game, hidden: !game.isHidden)
                        }
                        .tint(.gray)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if games.isEmpty {
                if store.loadingGames.contains(hostID) {
                    ProgressView {
                        Text("Loading apps…").artemisFont(.subheadline)
                    }
                } else {
                    ContentUnavailableView {
                        Label {
                            Text("No apps to show").artemisFont(.title2)
                        } icon: {
                            Image(systemName: "square.grid.2x2")
                        }
                    } description: {
                        Text("This PC has no apps, or they're hidden. To see hidden ones, choose Show All Apps, Including Hidden from the ⋯ menu.")
                            .artemisFont(.callout)
                    }
                }
            }
        }
        .navigationTitle(computer?.name ?? "Apps")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle(isOn: Binding(
                        get: { store.showingHiddenGames.contains(hostID) },
                        set: { show in
                            if show { store.showingHiddenGames.insert(hostID) } else { store.showingHiddenGames.remove(hostID) }
                        }
                    )) {
                        Label("Show All Apps, Including Hidden", systemImage: "eye")
                    }
                    Button("Refresh", systemImage: "arrow.clockwise") { store.refreshGames(hostID) }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .accessibilityIdentifier("games.more")
            }
        }
        .refreshable { store.refreshGames(hostID) }
        .alert(
            "\(store.runningGame(on: hostID)?.name ?? "An app") is active",
            isPresented: Binding(get: { switching != nil }, set: { if !$0 { switching = nil } }),
            presenting: switching
        ) { game in
            Button("Stop It and Open \(game.name)", role: .destructive) {
                store.endGame(on: hostID, thenStart: game)
            }
            if let running = store.runningGame(on: hostID) {
                Button("Resume \(running.name)") { store.play(running) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { game in
            Text("Stop \(store.runningGame(on: hostID)?.name ?? "the active app") on \(computer?.name ?? "the PC") and open \(game.name)? Unsaved work in it may be lost.")
        }
        .alert(
            "Stop \(ending?.name ?? "the app") on \(computer?.name ?? "the PC")?",
            isPresented: Binding(get: { ending != nil }, set: { if !$0 { ending = nil } }),
            presenting: ending
        ) { _ in
            Button("Stop", role: .destructive) { store.endGame(on: hostID) }
            Button("Cancel", role: .cancel) {}
        } message: { game in
            Text("\(game.name) closes on the PC. Unsaved work in it may be lost.")
        }
    }

    private func tapped(_ game: Game) {
        if let running = store.runningGame(on: hostID), running.appID != game.appID {
            switching = game
        } else {
            store.play(game)
        }
    }

    @ViewBuilder
    private func menu(for game: Game) -> some View {
        if game.isRunning {
            Button("Resume", systemImage: "play.fill") { store.play(game) }
            Button("Stop", systemImage: "stop.fill", role: .destructive) { ending = game }
        } else {
            Button("Connect", systemImage: "play.fill") { tapped(game) }
        }
        Divider()
        // As on the Mac: a hidden app can't connect by itself, and that app can't be hidden
        Toggle(isOn: Binding(get: { game.isDirectLaunch }, set: { store.setDirectLaunch(game, enabled: $0) })) {
            Label("Connect Automatically When Opening PC", systemImage: "bolt.fill")
        }
        .disabled(game.isHidden)
        if !game.isRunning {
            Button(game.isHidden ? "Show App" : "Hide App", systemImage: game.isHidden ? "eye" : "eye.slash") {
                store.setHidden(game, hidden: !game.isHidden)
            }
            .disabled(game.isDirectLaunch && !game.isHidden)
        }
    }
}

struct GameRow: View {
    let game: Game
    var onTap: () -> Void
    var onResume: () -> Void
    var onEnd: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Separate buttons with their own styles, so a tap on the row doesn't press Resume too.
        // An active app's buttons sit on the line under its name, beside the artwork, so the row
        // keeps a normal row's height: the row's button keeps room for them (an unseen copy) and
        // the real ones lie over it there. At the accessibility text sizes they go under the row.
        VStack(alignment: .leading, spacing: 8) {
            mainButton
                .overlayPreferenceValue(InlineButtonsAnchor.self) { anchor in
                    if let anchor, game.isRunning {
                        GeometryReader { proxy in
                            let frame = proxy[anchor]
                            buttons
                                .offset(x: frame.minX, y: frame.minY)
                        }
                    }
                }
            if game.isRunning && typeSize.isAccessibilitySize {
                buttons
            }
        }
        .padding(.vertical, 2)
    }

    @ScaledMetric(relativeTo: .body) private var dotSize: CGFloat = 8

    private var mainButton: some View {
        Button(action: onTap) {
            HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: 14) {
                art
                details
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("game.\(game.name)")
    }

    private var art: some View {
        BoxArtView(game: game)
            .frame(width: 54, height: 72)
            .opacity(game.isHidden ? 0.5 : 1)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(game.name)
                    .artemisFont(.bodyEmphasized)
                    .foregroundStyle(game.isHidden ? .secondary : .primary)
                if game.isRunning {
                    // A green dot after the name: the app is active
                    Circle()
                        .fill(.green)
                        .frame(width: dotSize, height: dotSize)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.bottom] + dotSize * 0.4 }
                        .accessibilityElement()
                        .accessibilityLabel("Active")
                        .accessibilityAddTraits(.isStaticText)
                        .accessibilityIdentifier("game.running")
                }
            }
            if game.isHidden {
                Label("Hidden", systemImage: "eye.slash")
                    .artemisFont(.caption)
                    .foregroundStyle(.secondary)
            }
            if game.isDirectLaunch {
                Label("Connects automatically", systemImage: "bolt.fill")
                    .artemisFont(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("game.directLaunch")
            }
            if game.isRunning && !typeSize.isAccessibilitySize {
                // Room for Resume and Stop, which lie over this
                buttons
                    .hidden()
                    .accessibilityHidden(true)
                    .anchorPreference(key: InlineButtonsAnchor.self, value: .bounds) { $0 }
                    .padding(.top, 2)
            }
        }
    }

    private var buttons: some View {
        GlassEffectContainer(spacing: 8) {
            // Side by side, or one above the other when the text is too large for that
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                Button(action: onResume) {
                    Label("Resume", systemImage: "play.fill")
                        .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil)
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("game.resume")
                Button(action: onEnd) {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Stop \(game.name)")
                .accessibilityIdentifier("game.end")
            }
            .labelStyle(.titleAndIcon)
            .artemisFont(typeSize.isAccessibilitySize ? .subheadline : .footnote)
            .controlSize(typeSize.isAccessibilitySize ? .regular : .small)
        }
    }
}

/// Where an active app's Resume and Stop go in its row: the room kept for them under the name.
private struct InlineButtonsAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

/// An app's artwork, or a placeholder until the PC has sent it.
struct BoxArtView: View {
    let game: Game
    @Environment(ComputerStore.self) private var store
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.fill.tertiary)
                Image(systemName: "macwindow")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
        }
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
        .accessibilityHidden(true)
        .task(id: "\(game.id)#\(store.boxArtRevision)") {
            if store.isDemo {
                image = DemoData.boxArt(for: game)
                return
            }
            guard let path = store.boxArtPath(for: game) else { return }
            let loaded = await Task.detached(priority: .userInitiated) {
                BoxArtCache.shared.image(atPath: path)
            }.value
            image = loaded
        }
    }
}
