//
//  ControlBar.swift
//  Artemis
//
//  The connected screen's Liquid Glass controls: the control bar (floating and movable in
//  landscape, foldable into a button; a row at the bottom when upright). The key row above
//  the keyboard is in KeyRow.swift.
//

import SwiftUI

struct ControlBar: View {
    let session: DesktopSession
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if session.isPortrait {
                docked
            } else if session.barExpanded {
                floating
            } else {
                folded
            }
        }
        // The bar stays a bar: icons are fixed, captions scale up to a point
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .animation(.snappy(duration: 0.25), value: session.barExpanded)
        .animation(.snappy(duration: 0.25), value: session.isZoomed)
    }

    // MARK: Layouts

    /// Upright: a full-width row under the desktop, with captions.
    private var docked: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 4) {
                buttons(captions: !typeSize.isAccessibilitySize)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
        }
        .padding(.horizontal, 10)
    }

    /// Landscape: a capsule over the desktop, dragged by its grip.
    private var floating: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 2) {
                grip
                buttons(captions: false)
                Button {
                    session.actions.setBarExpanded(false)
                } label: {
                    BarIcon(symbol: "chevron.compact.right", caption: nil)
                }
                .accessibilityLabel("Fold Control Bar")
                .accessibilityIdentifier("bar.fold")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    /// Folded into a round button that can be dragged anywhere.
    private var folded: some View {
        FoldedBar(session: session)
    }

    private var grip: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(90))
            .frame(width: 22, height: 44)
            .contentShape(.rect)
            .gesture(moveGesture)
            .accessibilityLabel("Move Control Bar")
            .accessibilityIdentifier("bar.grip")
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { session.actions.moveBar($0.translation) }
            .onEnded { _ in session.actions.endMoveBar() }
    }

    // MARK: Buttons

    @ViewBuilder
    private func buttons(captions: Bool) -> some View {
        Button {
            session.actions.toggleKeyboard()
        } label: {
            BarIcon(symbol: session.keyboardShown ? "keyboard.chevron.compact.down" : "keyboard",
                    caption: captions ? "Keyboard" : nil, active: session.keyboardShown)
        }
        .accessibilityLabel(session.keyboardShown ? "Hide Keyboard" : "Keyboard")
        .accessibilityIdentifier("bar.keyboard")

        Button {
            session.actions.setMode(session.mode == .trackpad ? .direct : .trackpad)
        } label: {
            BarIcon(symbol: session.mode == .trackpad ? "rectangle.and.hand.point.up.left" : "hand.point.up.left",
                    caption: captions ? (session.mode == .trackpad ? "Trackpad" : "Direct") : nil)
        }
        .accessibilityLabel(session.mode == .trackpad ? "Trackpad Mode" : "Direct Mode")
        .accessibilityHint("Switches between moving the pointer like a trackpad and touching the desktop directly")
        .accessibilityIdentifier("bar.mode")

        Button {
            session.actions.toggleGamepad()
        } label: {
            BarIcon(symbol: session.gamepadShown ? "gamecontroller.fill" : "gamecontroller",
                    caption: captions ? "Controller" : nil, active: session.gamepadShown)
        }
        .accessibilityLabel(session.gamepadShown ? "Hide Controller" : "Controller")
        .accessibilityHint("Shows a game controller on the screen; the PC sees it as an Xbox controller")
        .accessibilityIdentifier("bar.gamepad")

        Menu {
            // The everyday ones first; the rest in submenus, so the menu fits in landscape
            ForEach(Shortcut.common) { shortcut in
                Button(shortcut.title, systemImage: shortcut.symbol) { session.actions.shortcut(shortcut) }
            }
            Menu("More Editing", systemImage: "pencil") {
                ForEach(Shortcut.moreEditing) { shortcut in
                    Button(shortcut.title, systemImage: shortcut.symbol) { session.actions.shortcut(shortcut) }
                }
            }
            Menu("Windows", systemImage: "macwindow.on.rectangle") {
                ForEach(Shortcut.windows) { shortcut in
                    Button(shortcut.title, systemImage: shortcut.symbol) { session.actions.shortcut(shortcut) }
                }
            }
            Button("Type Clipboard", systemImage: "doc.on.clipboard.fill") { session.actions.typeClipboard() }
        } label: {
            BarIcon(symbol: "command", caption: captions ? "Shortcuts" : nil)
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Shortcuts")
        .accessibilityIdentifier("bar.shortcuts")

        // Upright, the reset button sits on the desktop's corner instead (DesktopViewController)
        if session.isZoomed && !session.isPortrait {
            Button {
                session.actions.resetZoom()
            } label: {
                BarIcon(symbol: "arrow.down.right.and.arrow.up.left", caption: captions ? "Fit" : nil)
            }
            .accessibilityLabel("Reset Zoom")
            .accessibilityIdentifier("bar.resetZoom")
            .transition(.scale.combined(with: .opacity))
        }

        Button {
            session.actions.disconnect()
        } label: {
            BarIcon(symbol: "xmark", caption: captions ? "Disconnect" : nil, tint: .red)
        }
        .accessibilityLabel("Disconnect")
        .accessibilityIdentifier("bar.disconnect")
    }
}

/// The folded bar: a round glass button that, left untouched for a few seconds, fades to a flat,
/// faint one so it hides over the desktop. A touch brings the glass back at once (and still
/// does what it does: a tap unfolds the bar, a drag moves it); the wait starts again after each.
private struct FoldedBar: View {
    let session: DesktopSession
    /// How long it stays glass after a touch.
    static var fadeDelay: Duration { .seconds(5) }

    @State private var faded = false
    /// Bumped by each touch: restarts the wait.
    @State private var touches = 0

    var body: some View {
        Image(systemName: "menubar.rectangle")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(faded ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .frame(width: 52, height: 52)
            .background {
                // Faded: a flat, muted disc instead of the glass
                Circle().fill(Color(white: 0.5).opacity(faded ? 0.35 : 0))
            }
            .contentShape(.circle)
            .glassEffect(faded ? .identity : .regular.interactive(), in: .circle)
            .opacity(faded ? 0.45 : 1)
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged {
                    wake()
                    session.actions.moveBar($0.translation)
                }
                .onEnded { _ in
                    wake()
                    session.actions.endMoveBar()
                })
            .onTapGesture {
                wake()
                session.actions.setBarExpanded(true)
            }
            .task(id: touches) {
                guard (try? await Task.sleep(for: Self.fadeDelay)) != nil else { return }
                withAnimation(.easeInOut(duration: 0.8)) { faded = true }
            }
            .accessibilityElement()
            .accessibilityLabel("Control Bar")
            .accessibilityValue(faded ? "Faded" : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                wake()
                session.actions.setBarExpanded(true)
            }
            .accessibilityIdentifier("bar.unfold")
    }

    private func wake() {
        if faded {
            withAnimation(.easeOut(duration: 0.15)) { faded = false }
        }
        touches &+= 1
    }
}

/// An icon of the bar, with an optional caption under it.
private struct BarIcon: View {
    let symbol: String
    let caption: String?
    var active = false
    var tint: Color? = nil

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .frame(height: 24)
            if let caption {
                Text(caption)
                    .artemisFont(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(tint ?? (active ? Color.accentColor : Color.primary))
        .frame(minWidth: 44, maxWidth: caption == nil ? nil : .infinity, minHeight: 44)
        .padding(.vertical, caption == nil ? 0 : 2)
        .contentShape(.rect)
    }
}
