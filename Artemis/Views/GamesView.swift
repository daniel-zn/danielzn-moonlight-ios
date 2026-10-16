//
//  GamesView.swift
//  Artemis
//
//  A PC's apps, as rows with their artwork and an Active badge, like the Mac app;
//  tapping connects to one or resumes the active session.
//

import SwiftUI

struct GamesView: View {
    let hostID: String
    @Environment(ComputerStore.self) private var store
    @State private var search = ""
    /// Opening another app while one is active: end that session first?
    @State private var switching: Game?
    /// Ending the active session.
    @State private var ending: Game?

    private var computer: Computer? { store.computer(hostID) }

    private var games: [Game] {
        let all = store.games(for: hostID)
        guard !search.isEmpty else { return all }
        return all.filter { $0.name.localizedStandardContains(search) }
    }

    var body: some View {
        List {
            ForEach(games) { game in
                GameRow(game: game, onTap: { tapped(game) }, onResume: { store.play(game) }, onEnd: { ending = game })
                .contextMenu { menu(for: game) } preview: {
                    BoxArtView(game: game)
                        .frame(width: 240, height: 320)
                }
                .swipeActions(edge: .trailing) {
                    if game.isRunning {
                        Button("End Session", systemImage: "stop.fill", role: .destructive) { ending = game }
                    } else {
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
                } else if !search.isEmpty {
                    ContentUnavailableView.search(text: search)
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
        .searchable(text: $search, prompt: "Search Apps")
        .searchToolbarBehavior(.minimize)
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
            Button("End It and Open \(game.name)", role: .destructive) {
                store.endGame(on: hostID, thenStart: game)
            }
            if let running = store.runningGame(on: hostID) {
                Button("Resume \(running.name)") { store.play(running) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { game in
            Text("End the session on \(computer?.name ?? "the PC") and open \(game.name)? Unsaved work in \(store.runningGame(on: hostID)?.name ?? "the active app") may be lost.")
        }
        .alert(
            "End the session on \(computer?.name ?? "the PC")?",
            isPresented: Binding(get: { ending != nil }, set: { if !$0 { ending = nil } }),
            presenting: ending
        ) { _ in
            Button("End Session", role: .destructive) { store.endGame(on: hostID) }
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
            Button("End Session", systemImage: "stop.fill", role: .destructive) { ending = game }
        } else {
            Button("Connect", systemImage: "play.fill") { tapped(game) }
            Button(game.isHidden ? "Show App" : "Hide App", systemImage: game.isHidden ? "eye" : "eye.slash") {
                store.setHidden(game, hidden: !game.isHidden)
            }
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
        // An active app's buttons sit under its name, which leaves the name room upright.
        VStack(alignment: .leading, spacing: 8) {
            mainButton
            if game.isRunning {
                buttons
                    .padding(.leading, typeSize.isAccessibilitySize ? 0 : 68)
            }
        }
        .padding(.vertical, 2)
    }

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
            Text(game.name)
                .artemisFont(.bodyEmphasized)
                .foregroundStyle(game.isHidden ? .secondary : .primary)
            if game.isRunning {
                Text("Active")
                    .artemisFont(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(.green, in: .capsule)
                    .accessibilityIdentifier("game.running")
            } else if game.isHidden {
                Label("Hidden", systemImage: "eye.slash")
                    .artemisFont(.caption)
                    .foregroundStyle(.secondary)
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
                    Label("End Session", systemImage: "stop.fill")
                        .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("End Session")
                .accessibilityIdentifier("game.end")
            }
            .labelStyle(.titleAndIcon)
            .artemisFont(.subheadline)
        }
    }
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
