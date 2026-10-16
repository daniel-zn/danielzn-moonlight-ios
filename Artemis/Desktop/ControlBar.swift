//
//  ControlBar.swift
//  Artemis
//
//  The connected screen's Liquid Glass controls: the control bar (floating and movable in
//  landscape, foldable into a button; a row under the desktop when upright) and the key
//  row above the keyboard.
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
        Image(systemName: "menubar.rectangle")
            .font(.system(size: 20, weight: .medium))
            .frame(width: 52, height: 52)
            .contentShape(.circle)
            .glassEffect(.regular.interactive(), in: .circle)
            .gesture(moveGesture)
            .onTapGesture { session.actions.setBarExpanded(true) }
            .accessibilityElement()
            .accessibilityLabel("Control Bar")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { session.actions.setBarExpanded(true) }
            .accessibilityIdentifier("bar.unfold")
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
            session.actions.rightClick()
        } label: {
            BarIcon(symbol: "contextualmenu.and.cursorarrow", caption: captions ? "Right Click" : nil)
        }
        .accessibilityLabel("Right Click")
        .accessibilityIdentifier("bar.rightClick")

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

        Menu {
            Button("Disconnect", systemImage: "xmark.circle", role: .destructive) { session.actions.disconnect() }
        } label: {
            BarIcon(symbol: "xmark", caption: captions ? "Disconnect" : nil, tint: .red)
        }
        .accessibilityLabel("Disconnect")
        .accessibilityIdentifier("bar.disconnect")
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

// MARK: - Key row

/// The keys above the iOS keyboard: Esc, Tab, the sticky modifiers, arrows and editing keys,
/// and a page of function keys.
struct KeyRow: View {
    let session: DesktopSession

    var body: some View {
        HStack(spacing: 6) {
            // The page switch stays at the start, outside the scrolling keys
            Group {
                if session.keyPage == .main {
                    KeyCap(title: "Fn", identifier: "key.page", accessibility: "Function Keys") { session.keyPage = .function }
                } else {
                    KeyCap(symbol: "chevron.left", identifier: "key.page", accessibility: "Back to Keys") { session.keyPage = .main }
                }
            }
            .padding(.leading, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        if session.keyPage == .main {
                            mainPage
                        } else {
                            functionPage
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
            .scrollClipDisabled()
            .mask(Rectangle().padding(.horizontal, -2))
            Button {
                session.actions.toggleKeyboard()
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 38)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide Keyboard")
            .accessibilityIdentifier("key.hide")
            .padding(.trailing, 8)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    @ViewBuilder
    private var mainPage: some View {
        KeyCap(title: "Esc", identifier: "key.Esc") { session.actions.key(KeyCode.escape) }
        KeyCap(title: "Tab", identifier: "key.Tab") { session.actions.key(KeyCode.tab) }
        ForEach([Modifier.ctrl, .alt, .win, .shift]) { modifier in
            KeyCap(title: modifier.title, identifier: "key.\(modifier.title)", state: session.state(of: modifier)) {
                session.tapModifier(modifier)
            }
        }
        KeyCap(symbol: "arrow.left", identifier: "key.Left", accessibility: "Left Arrow") { session.actions.key(KeyCode.left) }
        KeyCap(symbol: "arrow.up", identifier: "key.Up", accessibility: "Up Arrow") { session.actions.key(KeyCode.up) }
        KeyCap(symbol: "arrow.down", identifier: "key.Down", accessibility: "Down Arrow") { session.actions.key(KeyCode.down) }
        KeyCap(symbol: "arrow.right", identifier: "key.Right", accessibility: "Right Arrow") { session.actions.key(KeyCode.right) }
        KeyCap(title: "Del", identifier: "key.Del", accessibility: "Delete") { session.actions.key(KeyCode.delete) }
        KeyCap(title: "Home", identifier: "key.Home") { session.actions.key(KeyCode.home) }
        KeyCap(title: "End", identifier: "key.End") { session.actions.key(KeyCode.end) }
        KeyCap(title: "PgUp", identifier: "key.PgUp", accessibility: "Page Up") { session.actions.key(KeyCode.pageUp) }
        KeyCap(title: "PgDn", identifier: "key.PgDn", accessibility: "Page Down") { session.actions.key(KeyCode.pageDown) }
    }

    @ViewBuilder
    private var functionPage: some View {
        ForEach(1...12, id: \.self) { number in
            KeyCap(title: "F\(number)", identifier: "key.F\(number)") {
                session.actions.key(KeyCode.f1 + UInt16(number - 1))
            }
        }
    }
}

private struct KeyCap: View {
    var title: String?
    var symbol: String?
    let identifier: String
    var accessibility: String?
    var state = DesktopSession.ModifierState.off
    let action: () -> Void

    init(title: String, identifier: String, accessibility: String? = nil, state: DesktopSession.ModifierState = .off, action: @escaping () -> Void) {
        self.title = title
        self.identifier = identifier
        self.accessibility = accessibility
        self.state = state
        self.action = action
    }

    init(symbol: String, identifier: String, accessibility: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.identifier = identifier
        self.accessibility = accessibility
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                } else if let title {
                    Text(title)
                        .artemisFont(.subheadline)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(state == .off ? Color.primary : Color.white)
            .padding(.horizontal, 10)
            .frame(minWidth: 44, minHeight: 38)
            .overlay(alignment: .topTrailing) {
                if state == .locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                }
            }
            .glassEffect(state == .off ? .regular.interactive() : .regular.tint(.accentColor).interactive(),
                         in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility ?? title ?? "")
        .accessibilityValue(state == .off ? "" : (state == .locked ? "Locked" : "Held"))
        .accessibilityIdentifier(identifier)
        .sensoryFeedback(.selection, trigger: state)
    }
}
