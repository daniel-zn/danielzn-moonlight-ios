// SPDX-License-Identifier: GPL-3.0-or-later
//
//  PadTouch.swift
//  Artemis
//
//  The on-screen controller's touches: RetroPlay's PadTouchView (RetroPlayApp/Controls/
//  PadTouchSurface.swift) line for line, with Artemis's controls in place of its regions and a
//  second stick. Kept free of Moonlight's headers so Scripts/pad-parity can build it next to
//  RetroPlay's own file and feed both the same touches (docs/TOUCH.md, "Sticks and D-pad").
//

import SwiftUI
import UIKit

/// One control on the pad, with its frame in the pad's view.
struct PadControl: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Held while touched: Moonlight's button flags (or a trigger's bit).
        case button(UInt32)
        /// 8-way pad; the touch that lands on it keeps steering it even off the edge.
        case dpad(up: UInt32, down: UInt32, left: UInt32, right: UInt32)
        /// Analog stick; the touch that lands on it keeps steering it.
        case stick(left: Bool)
    }

    enum Look: Equatable {
        case face(Color)
        case shoulder
        /// Select and Start.
        case pill
        /// L3 and R3: small and round.
        case click
        case guide
        case dpad
        case stick
    }

    let id: String
    let title: String
    let accessibility: String
    let kind: Kind
    let look: Look
    let frame: CGRect

    /// RetroPlay's `PadHitShape.circle` (its face buttons and stick); the rest are rectangles.
    var isRound: Bool {
        switch look {
        case .face, .click, .guide, .stick: true
        default: false
        }
    }
}

/// What the pad holds: buttons (with the trigger bits) and the sticks, −1…1 with up positive
/// (RetroPlay's `PadTouchOutput`, with a second stick).
struct PadHeld: Equatable {
    var buttons: UInt32 = 0
    var leftX: Float = 0, leftY: Float = 0
    var rightX: Float = 0, rightY: Float = 0

    static let idle = PadHeld()

    /// −1…1 to an Xbox controller's stick axis, −32768…32767: full tilt reaches each end.
    static func xboxAxis(_ value: Float) -> Int16 {
        let clamped = min(max(value, -1), 1)
        return Int16((clamped < 0 ? clamped * 32768 : clamped * 32767).rounded())
    }
}

/// Every touch on the pad. That is what makes the controls feel like a pad (RetroPlay's words):
///
/// * any number of fingers at once (a stick + two face buttons + a trigger),
/// * slide a thumb between face buttons without lifting (rolling B → A),
/// * press the gap between two buttons to hold both,
/// * a D-pad / stick touch keeps steering after drifting off the graphic,
/// * a slightly-missed tap snaps to the nearest control,
/// * haptic tick on every new press.
///
/// Touches that start away from every control fall through to the desktop.
final class PadTouchView: UIView {
    var controls: [PadControl] = [] {
        didSet {
            if controls != oldValue { reconcileTracks() }
        }
    }
    var hapticsEnabled = true
    var onChange: ((PadHeld) -> Void)?

    /// Extra reach around each control, in points.
    private let slop: CGFloat = 14
    /// Buttons are hit a little outside their drawn circle so neighbours overlap (combo zone).
    private let buttonReach: CGFloat = 1.12

    /// How far the knob moves from the centre at full tilt, as a fraction of the stick's size
    /// (RetroPlay's `PadStick.travelFraction`).
    static let travelFraction: CGFloat = 0.30
    /// How far the thumb moves for full tilt: three quarters of the knob's travel (RetroPlay's
    /// `PadStick.touchTravelFraction`). A thumb's touch point sits a little inside where it
    /// feels it's pressing, so at 1:1 a full push often read as 70–80 %. Past this it holds
    /// full tilt.
    static let touchTravelFraction: CGFloat = travelFraction * 0.75

    private enum Mode {
        case buttons(UInt32)
        case dpad(controlID: String, bits: UInt32)
        case stick(controlID: String, left: Bool, stick: TouchStick, x: Float, y: Float)
    }

    private var tracks: [ObjectIdentifier: Mode] = [:]
    private var lastOutput = PadHeld.idle
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        isOpaque = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Only touches that land on (or near) a control are the pad's.
    func claims(_ point: CGPoint) -> Bool {
        nearestControl(to: point) != nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if hapticsEnabled { haptics.prepare() }
        for touch in touches {
            began(ObjectIdentifier(touch), at: touch.location(in: self))
        }
        emit()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            moved(ObjectIdentifier(touch), to: touch.location(in: self))
        }
        emit()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            ended(ObjectIdentifier(touch))
        }
        emit()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { forgetTouches() }
    }

    /// Every finger lifts (the pad hides, the app goes away).
    func forgetTouches() {
        tracks.removeAll()
        emit()
    }

    /// A finger lands at `p` (view space): it takes the control there, if any.
    func began(_ key: ObjectIdentifier, at p: CGPoint) {
        guard let control = nearestControl(to: p) else { return }
        switch control.kind {
        case .button:
            tracks[key] = .buttons(buttonBits(at: p, fallback: control))
        case .dpad:
            tracks[key] = .dpad(controlID: control.id, bits: dpadBits(control, p))
        case .stick(let left):
            // Absolute: the stick's centre is zero, and the knob goes where the thumb is.
            var stick = TouchStick(
                originX: Double(control.frame.midX),
                originY: Double(control.frame.midY),
                radius: stickTravel(control)
            )
            let v = stick.update(x: Double(p.x), y: Double(p.y))
            tracks[key] = .stick(controlID: control.id, left: left, stick: stick, x: Float(v.x), y: Float(v.y))
        }
    }

    /// A held finger moves to `p`: its control follows.
    func moved(_ key: ObjectIdentifier, to p: CGPoint) {
        guard let mode = tracks[key] else { return }
        switch mode {
        case .buttons(let old):
            // Slide between face buttons; keep the old press if the thumb wanders into a gap.
            let bits = buttonBits(at: p, fallback: nil)
            tracks[key] = .buttons(bits == 0 && isNearAnyButton(p) ? old : bits)
        case .dpad(let id, _):
            guard let control = controlWithID(id) else { return }
            tracks[key] = .dpad(controlID: id, bits: dpadBits(control, p))
        case .stick(let id, let left, var stick, _, _):
            let v = stick.update(x: Double(p.x), y: Double(p.y))
            tracks[key] = .stick(controlID: id, left: left, stick: stick, x: Float(v.x), y: Float(v.y))
        }
    }

    /// A finger lifts.
    func ended(_ key: ObjectIdentifier) {
        tracks[key] = nil
    }

    // MARK: Geometry

    private func controlWithID(_ id: String) -> PadControl? {
        controls.first { $0.id == id }
    }

    /// Drop tracks whose control disappeared (layout / rotation change).
    private func reconcileTracks() {
        var changed = false
        for (key, mode) in tracks {
            let id: String?
            switch mode {
            case .buttons: id = nil
            case .dpad(let c, _), .stick(let c, _, _, _, _): id = c
            }
            if let id, controlWithID(id) == nil {
                tracks[key] = nil
                changed = true
            }
        }
        if changed {
            DispatchQueue.main.async { [weak self] in self?.emit() }
        }
    }

    private func distance(from p: CGPoint, to control: PadControl) -> CGFloat {
        let frame = control.frame
        if control.isRound {
            let r = min(frame.width, frame.height) / 2
            let d = hypot(p.x - frame.midX, p.y - frame.midY)
            return max(0, d - r)
        }
        let dx = max(frame.minX - p.x, 0, p.x - frame.maxX)
        let dy = max(frame.minY - p.y, 0, p.y - frame.maxY)
        return hypot(dx, dy)
    }

    /// Control under the point, else the closest one within `slop`.
    private func nearestControl(to p: CGPoint) -> PadControl? {
        var best: PadControl?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for control in controls {
            let d = distance(from: p, to: control)
            if d <= slop && d < bestDistance {
                best = control
                bestDistance = d
                if d == 0 { break }
            }
        }
        return best
    }

    private func isNearAnyButton(_ p: CGPoint) -> Bool {
        controls.contains { control in
            if case .button = control.kind { return distance(from: p, to: control) <= slop }
            return false
        }
    }

    /// Every button whose (slightly enlarged) area contains `p` — two at once in the gap.
    private func buttonBits(at p: CGPoint, fallback: PadControl?) -> UInt32 {
        var bits: UInt32 = 0
        var nearest: (bits: UInt32, distance: CGFloat)?
        for control in controls {
            guard case .button(let b) = control.kind else { continue }
            let frame = control.frame
            let hit: Bool
            if control.isRound {
                let r = min(frame.width, frame.height) / 2 * buttonReach
                hit = hypot(p.x - frame.midX, p.y - frame.midY) <= r
            } else {
                hit = frame.contains(p)
            }
            if hit {
                bits |= b
            } else {
                let d = distance(from: p, to: control)
                if d <= slop, d < (nearest?.distance ?? .greatestFiniteMagnitude) {
                    nearest = (b, d)
                }
            }
        }
        if bits != 0 { return bits }
        if let nearest { return nearest.bits }
        if let fallback, case .button(let b) = fallback.kind { return b }
        return 0
    }

    private func dpadBits(_ control: PadControl, _ p: CGPoint) -> UInt32 {
        guard case .dpad(let up, let down, let left, let right) = control.kind else { return 0 }
        let dx = Double(p.x - control.frame.midX)
        let dy = Double(p.y - control.frame.midY)
        let size = Double(min(control.frame.width, control.frame.height))
        let dirs = PadHitTesting.dpad(dx: dx, dy: dy, deadzone: size * 0.12, diagonalRatio: 0.42)
        var bits: UInt32 = 0
        if dirs.up { bits |= up }
        if dirs.down { bits |= down }
        if dirs.left { bits |= left }
        if dirs.right { bits |= right }
        return bits
    }

    /// Thumb travel for full tilt: a little less than the knob's own travel
    /// (`touchTravelFraction`), so a natural full push always reaches 100%.
    private func stickTravel(_ control: PadControl) -> Double {
        Double(min(control.frame.width, control.frame.height) * Self.touchTravelFraction)
    }

    // MARK: Output

    private func emit(haptic: Bool = true) {
        var out = PadHeld.idle
        for mode in tracks.values {
            switch mode {
            case .buttons(let bits), .dpad(_, let bits):
                out.buttons |= bits
            case .stick(_, let left, _, let x, let y):
                if left {
                    out.leftX = x
                    out.leftY = y
                } else {
                    out.rightX = x
                    out.rightY = y
                }
            }
        }
        guard out != lastOutput else { return }
        let newlyPressed = out.buttons & ~lastOutput.buttons
        if haptic && hapticsEnabled && newlyPressed != 0 {
            haptics.impactOccurred(intensity: 0.7)
        }
        lastOutput = out
        onChange?(out)
    }
}
