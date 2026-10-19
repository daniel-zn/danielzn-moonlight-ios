//
//  OnScreenGamepad.swift
//  Artemis
//
//  The on-screen controller (the control bar's controller button): an Xbox-style gamepad of
//  Liquid Glass buttons that the PC sees as an Xbox controller. Upright it takes the trackpad's
//  place; in landscape it lies over the desktop, see-through, at the screen's sides.
//  Adapted from RetroPlay's pad (Controls/PadControls.swift, PadTouchSurface.swift): SwiftUI
//  draws the controls, one UIKit view takes every touch on them, so several fingers work at
//  once (a stick, a trigger and a face button), a thumb slides between face buttons, a stick
//  measures from where the thumb lands, and a new press ticks a haptic. Touches away from the
//  controls fall through to the desktop.
//

import SwiftUI
import UIKit

// MARK: - Controls and layout

/// One control on the pad, with its frame in the pad's view.
struct PadControl: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Held while touched: Moonlight's button flags (or a trigger's bit).
        case button(UInt32)
        case dpad
        case stick(left: Bool)
    }

    enum Look: Equatable {
        case face(Color)
        case shoulder
        case pill
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

    var isRound: Bool {
        switch look {
        case .face, .guide, .stick: true
        default: false
        }
    }
}

enum PadBits {
    static let a = UInt32(A_FLAG), b = UInt32(B_FLAG), x = UInt32(X_FLAG), y = UInt32(Y_FLAG)
    static let up = UInt32(UP_FLAG), down = UInt32(DOWN_FLAG), left = UInt32(LEFT_FLAG), right = UInt32(RIGHT_FLAG)
    static let lb = UInt32(LB_FLAG), rb = UInt32(RB_FLAG)
    static let view = UInt32(BACK_FLAG), menu = UInt32(PLAY_FLAG), guide = UInt32(SPECIAL_FLAG)
    /// The triggers ride along as bits of their own (Moonlight's flags don't use these) and go
    /// out as fully pulled.
    static let leftTrigger: UInt32 = 1 << 30
    static let rightTrigger: UInt32 = 1 << 31
    static let triggers = leftTrigger | rightTrigger
}

enum PadLayout {
    /// Settings › Controllers › On-screen controller size: a share of the space it gets
    /// (Large fills it).
    static let sizes: [(name: String, scale: Double)] = [("Small", 0.8), ("Medium", 0.9), ("Large", 1)]
    static let defaultSize = 0.9

    private static let xbox = (a: Color(red: 0.36, green: 0.72, blue: 0.26), b: Color(red: 0.86, green: 0.24, blue: 0.22),
                               x: Color(red: 0.20, green: 0.50, blue: 0.95), y: Color(red: 0.95, green: 0.74, blue: 0.10))

    /// The controls for a pad of this size: upright, a block the shape of the space it gets
    /// (the trackpad's); in landscape, a column at each side of `safe` and the small buttons
    /// at the top in the middle.
    static func controls(size: CGSize, safe: CGRect, landscape: Bool, scale: Double) -> [PadControl] {
        landscape ? sides(safe: safe, scale: scale) : block(size: size, scale: scale)
    }

    /// Upright: shoulders across the top, View / Guide / Menu under them, then the left stick
    /// and A B X Y, then the D-pad and the right stick (an Xbox controller's offset sticks).
    private static func block(size: CGSize, scale: Double) -> [PadControl] {
        let design = CGSize(width: 380, height: 420)
        let unit = max(0.4, min(size.width / design.width, size.height / design.height) * min(scale, 1))
        let origin = CGPoint(x: (size.width - design.width * unit) / 2, y: (size.height - design.height * unit) / 2)
        func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: origin.x + x * unit, y: origin.y + y * unit, width: width * unit, height: height * unit)
        }
        func round(_ x: CGFloat, _ y: CGFloat, _ diameter: CGFloat) -> CGRect {
            rect(x - diameter / 2, y - diameter / 2, diameter, diameter)
        }
        return shoulders(lt: rect(4, 4, 80, 40), lb: rect(92, 4, 80, 40), rb: rect(208, 4, 80, 40), rt: rect(296, 4, 80, 40))
            + middle(view: rect(108, 64, 52, 32), guide: round(190, 80, 44), menu: rect(220, 64, 52, 32))
            + [stick(left: true, round(80, 175, 130))]
            + face(center: CGPoint(x: origin.x + 295 * unit, y: origin.y + 175 * unit), diameter: 54 * unit, reach: 50 * unit)
            + [dpad(round(110, 335, 130)), stick(left: false, round(270, 335, 130))]
    }

    /// Landscape: the left column (LT LB, the left stick, the D-pad further in), the right one
    /// mirrored (RB RT, A B X Y, the right stick further in), View / Guide / Menu top centre.
    private static func sides(safe: CGRect, scale: Double) -> [PadControl] {
        let unit = sidesUnit(safe: safe, scale: scale)
        func left(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: safe.minX + x * unit, y: safe.minY + y * unit, width: width * unit, height: height * unit)
        }
        // The right column is the left one mirrored
        func right(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: safe.maxX - (x + width) * unit, y: safe.minY + y * unit, width: width * unit, height: height * unit)
        }
        func round(_ place: (CGFloat, CGFloat, CGFloat, CGFloat) -> CGRect, _ x: CGFloat, _ y: CGFloat, _ diameter: CGFloat) -> CGRect {
            place(x - diameter / 2, y - diameter / 2, diameter, diameter)
        }
        let guide = CGRect(x: safe.midX - 22 * unit, y: safe.minY, width: 44 * unit, height: 44 * unit)
        let faceCenter = right(80, 125, 0, 0).origin
        return shoulders(lt: left(0, 0, 80, 40), lb: left(88, 0, 80, 40), rb: right(88, 0, 80, 40), rt: right(0, 0, 80, 40))
            + middle(view: CGRect(x: guide.minX - 60 * unit, y: guide.midY - 16 * unit, width: 52 * unit, height: 32 * unit),
                     guide: guide,
                     menu: CGRect(x: guide.maxX + 8 * unit, y: guide.midY - 16 * unit, width: 52 * unit, height: 32 * unit))
            + [stick(left: true, round(left, 75, 125, 130))]
            + face(center: faceCenter, diameter: 54 * unit, reach: 50 * unit)
            + [dpad(round(left, 160, 255, 120)), stick(left: false, round(right, 160, 255, 120))]
    }

    /// Where the control bar goes while the pad lies over the desktop: top centre, under
    /// View / Guide / Menu (as a fraction of the screen).
    static func barCenter(safe: CGRect, bounds: CGSize, barHeight: CGFloat, scale: Double) -> CGPoint {
        let y = safe.minY + 44 * sidesUnit(safe: safe, scale: scale) + 10 + barHeight / 2
        return CGPoint(x: safe.midX / bounds.width, y: y / bounds.height)
    }

    /// Landscape's size: two columns of 230 × 320 and 170 between them, at most 1.3×.
    private static func sidesUnit(safe: CGRect, scale: Double) -> CGFloat {
        max(0.4, min(safe.height / 320, safe.width / (230 * 2 + 170), 1.3) * min(scale, 1))
    }

    private static func shoulders(lt: CGRect, lb: CGRect, rb: CGRect, rt: CGRect) -> [PadControl] {
        [PadControl(id: "LT", title: "LT", accessibility: "Left Trigger", kind: .button(PadBits.leftTrigger), look: .shoulder, frame: lt),
         PadControl(id: "LB", title: "LB", accessibility: "Left Bumper", kind: .button(PadBits.lb), look: .shoulder, frame: lb),
         PadControl(id: "RB", title: "RB", accessibility: "Right Bumper", kind: .button(PadBits.rb), look: .shoulder, frame: rb),
         PadControl(id: "RT", title: "RT", accessibility: "Right Trigger", kind: .button(PadBits.rightTrigger), look: .shoulder, frame: rt)]
    }

    private static func middle(view: CGRect, guide: CGRect, menu: CGRect) -> [PadControl] {
        [PadControl(id: "View", title: "View", accessibility: "View", kind: .button(PadBits.view), look: .pill, frame: view),
         PadControl(id: "Guide", title: "", accessibility: "Xbox Button", kind: .button(PadBits.guide), look: .guide, frame: guide),
         PadControl(id: "Menu", title: "Menu", accessibility: "Menu", kind: .button(PadBits.menu), look: .pill, frame: menu)]
    }

    private static func face(center: CGPoint, diameter: CGFloat, reach: CGFloat) -> [PadControl] {
        func at(_ dx: CGFloat, _ dy: CGFloat) -> CGRect {
            CGRect(x: center.x + dx * reach - diameter / 2, y: center.y + dy * reach - diameter / 2, width: diameter, height: diameter)
        }
        return [PadControl(id: "Y", title: "Y", accessibility: "Y", kind: .button(PadBits.y), look: .face(xbox.y), frame: at(0, -1)),
                PadControl(id: "X", title: "X", accessibility: "X", kind: .button(PadBits.x), look: .face(xbox.x), frame: at(-1, 0)),
                PadControl(id: "B", title: "B", accessibility: "B", kind: .button(PadBits.b), look: .face(xbox.b), frame: at(1, 0)),
                PadControl(id: "A", title: "A", accessibility: "A", kind: .button(PadBits.a), look: .face(xbox.a), frame: at(0, 1))]
    }

    private static func dpad(_ frame: CGRect) -> PadControl {
        PadControl(id: "dpad", title: "", accessibility: "D-pad", kind: .dpad, look: .dpad, frame: frame)
    }

    private static func stick(left: Bool, _ frame: CGRect) -> PadControl {
        PadControl(id: left ? "leftStick" : "rightStick", title: "", accessibility: left ? "Left Stick" : "Right Stick",
                   kind: .stick(left: left), look: .stick, frame: frame)
    }
}

// MARK: - State

/// What the pad holds: buttons (with the trigger bits) and the sticks, −1…1 with up positive.
struct PadHeld: Equatable {
    var buttons: UInt32 = 0
    var left = CGVector.zero
    var right = CGVector.zero

    static let idle = PadHeld()

    /// As Moonlight sends it.
    var gamepadState: GamepadState {
        func axis(_ value: CGFloat) -> Int16 { Int16((min(max(value, -1), 1) * 32767).rounded()) }
        return GamepadState(buttons: buttons & ~PadBits.triggers,
                            leftTrigger: buttons & PadBits.leftTrigger != 0 ? 255 : 0,
                            rightTrigger: buttons & PadBits.rightTrigger != 0 ? 255 : 0,
                            leftX: axis(left.dx), leftY: axis(left.dy), rightX: axis(right.dx), rightY: axis(right.dy))
    }
}

@Observable
final class OnScreenGamepadModel {
    var controls: [PadControl] = []
    var landscape = false
    var opacity = 1.0
    private(set) var held = PadHeld.idle
    /// Called with each new state.
    @ObservationIgnored var onChange: ((PadHeld) -> Void)?
    /// The touch view's own touches (set by it) and VoiceOver's presses (added on top).
    @ObservationIgnored private var touched = PadHeld.idle
    @ObservationIgnored private var pulsed = PadHeld.idle
    @ObservationIgnored private var pulseCount = 0

    func isHeld(_ bits: UInt32) -> Bool {
        held.buttons & bits == bits
    }

    func setTouched(_ state: PadHeld) {
        touched = state
        publish()
    }

    /// Everything up (the pad hides, the session ends).
    func releaseAll() {
        touched = .idle
        pulsed = .idle
        publish()
    }

    /// A press for VoiceOver (and Switch Control): held for a moment.
    func pulse(buttons: UInt32 = 0, left: CGVector = .zero, right: CGVector = .zero) {
        pulsed = PadHeld(buttons: buttons, left: left, right: right)
        pulseCount += 1
        let count = pulseCount
        publish()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            // A newer press keeps going
            guard let self, self.pulseCount == count else { return }
            self.pulsed = .idle
            self.publish()
        }
    }

    private func publish() {
        var next = touched
        next.buttons |= pulsed.buttons
        if pulsed.left != .zero { next.left = pulsed.left }
        if pulsed.right != .zero { next.right = pulsed.right }
        guard next != held else { return }
        held = next
        onChange?(next)
    }
}

// MARK: - The view

/// The pad: SwiftUI's drawing with the touch view over it. Hit-tests through to the desktop
/// away from the controls.
final class OnScreenGamepadView: UIView {
    let model = OnScreenGamepadModel()
    private(set) lazy var host = UIHostingController(rootView: OnScreenGamepadDrawing(model: model))
    private let touchView = PadTouchView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        host.view.backgroundColor = .clear
        // Nothing here moves for the keyboard
        host.safeAreaRegions = []
        addSubview(host.view)
        touchView.model = model
        addSubview(touchView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Lays the controls out for this size; `safe` is where landscape's columns go.
    func layout(landscape: Bool, safe: CGRect, scale: Double, opacity: Double) {
        host.view.frame = bounds
        touchView.frame = bounds
        let controls = PadLayout.controls(size: bounds.size, safe: safe, landscape: landscape, scale: scale)
        if model.controls != controls { model.controls = controls }
        if model.landscape != landscape { model.landscape = landscape }
        let opacity = landscape ? opacity : 1
        if model.opacity != opacity { model.opacity = opacity }
        touchView.controls = controls
    }

    /// Fingers lift (the pad hides, the app goes away).
    func releaseAll() {
        touchView.forgetTouches()
        model.releaseAll()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, touchView.claims(convert(point, to: touchView)) else { return nil }
        return touchView
    }
}

/// The controls' drawing (no gestures: PadTouchView takes the touches).
struct OnScreenGamepadDrawing: View {
    let model: OnScreenGamepadModel

    var body: some View {
        // One container renders the controls' glass together (cheaper than a pass each); no
        // spacing, so neighbouring controls don't melt into one another
        GlassEffectContainer(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(model.controls) { control in
                    PadControlView(control: control, model: model)
                        .frame(width: control.frame.width, height: control.frame.height)
                        .position(x: control.frame.midX, y: control.frame.midY)
                }
            }
        }
        .opacity(model.opacity)
        .ignoresSafeArea()
        // The pad's labels are drawn at its own size, not the text size
        .dynamicTypeSize(.large)
    }
}

private struct PadControlView: View {
    let control: PadControl
    let model: OnScreenGamepadModel

    var body: some View {
        Group {
            switch control.look {
            case .face(let color): face(color)
            case .shoulder: flat(shape: RoundedRectangle(cornerRadius: control.frame.height * 0.32, style: .continuous))
            case .pill: flat(shape: Capsule())
            case .guide: guide
            case .dpad: dpad
            case .stick: stick
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(control.accessibility)
        .accessibilityIdentifier("pad.\(control.id)")
        .modifier(PadAccessibilityActions(control: control, model: model))
    }

    private var landscape: Bool { model.landscape }

    private var bits: UInt32 {
        if case .button(let bits) = control.kind { return bits }
        return 0
    }

    private func label(_ size: CGFloat) -> Font {
        .custom(Typography.postScriptName, fixedSize: size)
    }

    /// Over the desktop the glass is clear, so the picture shows; upright it's the regular one.
    private func glass(tint: Color?, held: Bool) -> Glass {
        if held { return .regular.tint((tint ?? .accentColor).opacity(0.85)) }
        // Over the desktop: clear glass, a little darkened so it reads over white windows and in dark mode
        if landscape { return tint.map { .clear.tint($0.opacity(0.25)) } ?? .clear.tint(.black.opacity(0.22)) }
        return tint.map { .regular.tint($0.opacity(0.7)) } ?? .regular
    }

    private var ink: Color {
        landscape ? .white : .primary
    }

    private func face(_ color: Color) -> some View {
        let held = model.isHeld(bits)
        let diameter = control.frame.width
        return Text(control.title)
            .font(label(diameter * 0.4))
            .foregroundStyle(landscape && !held ? color : .white)
            .shadow(color: .black.opacity(landscape ? 0.5 : 0), radius: 2)
            .frame(width: diameter, height: diameter)
            .glassEffect(glass(tint: color, held: held), in: .circle)
            .scaleEffect(held ? 0.92 : 1)
            .animation(.easeOut(duration: 0.06), value: held)
            .accessibilityAddTraits(.isButton)
    }

    private func flat<S: Shape>(shape: S) -> some View {
        let held = model.isHeld(bits)
        return Text(control.title)
            .font(label(min(control.frame.height * 0.42, 17)))
            .foregroundStyle(held ? .white : ink)
            .shadow(color: .black.opacity(landscape ? 0.5 : 0), radius: 2)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: control.frame.width, height: control.frame.height)
            .glassEffect(glass(tint: nil, held: held), in: shape)
            .scaleEffect(held ? 0.95 : 1)
            .animation(.easeOut(duration: 0.06), value: held)
            .accessibilityAddTraits(.isButton)
    }

    private var guide: some View {
        let held = model.isHeld(bits)
        return Image(systemName: "xbox.logo")
            .font(.system(size: control.frame.width * 0.48, weight: .medium))
            .foregroundStyle(held ? .white : ink)
            .shadow(color: .black.opacity(landscape ? 0.5 : 0), radius: 2)
            .frame(width: control.frame.width, height: control.frame.height)
            .glassEffect(glass(tint: nil, held: held), in: .circle)
            .scaleEffect(held ? 0.92 : 1)
            .animation(.easeOut(duration: 0.06), value: held)
            .accessibilityAddTraits(.isButton)
    }

    private var dpad: some View {
        let size = control.frame.width
        let arm = size * 0.36
        let travel = (size - arm) / 2
        return ZStack {
            Color.clear.glassEffect(glass(tint: nil, held: false), in: PlusShape(armThickness: arm))
            ForEach([(PadBits.up, "arrowtriangle.up.fill", CGSize(width: 0, height: -travel)),
                     (PadBits.down, "arrowtriangle.down.fill", CGSize(width: 0, height: travel)),
                     (PadBits.left, "arrowtriangle.left.fill", CGSize(width: -travel, height: 0)),
                     (PadBits.right, "arrowtriangle.right.fill", CGSize(width: travel, height: 0))], id: \.0) { bits, symbol, offset in
                let held = model.isHeld(bits)
                ZStack {
                    RoundedRectangle(cornerRadius: arm * 0.2, style: .continuous)
                        .fill(Color.accentColor.opacity(held ? 0.85 : 0))
                        .frame(width: arm * 0.86, height: arm * 0.86)
                    Image(systemName: symbol)
                        .font(.system(size: max(8, arm * 0.28), weight: .bold))
                        .foregroundStyle(held ? Color.white : ink.opacity(0.7))
                        .shadow(color: .black.opacity(landscape ? 0.6 : 0), radius: 2)
                }
                .offset(offset)
                .animation(.easeOut(duration: 0.06), value: held)
            }
        }
        .frame(width: size, height: size)
        .accessibilityAddTraits(.isButton)
    }

    private var stick: some View {
        let size = control.frame.width
        let travel = size * 0.3
        let left = control.kind == .stick(left: true)
        let value = left ? model.held.left : model.held.right
        let moved = value != .zero
        return ZStack {
            Color.clear.glassEffect(glass(tint: nil, held: false), in: .circle)
            Color.clear
                .frame(width: size * 0.46, height: size * 0.46)
                .glassEffect(moved ? .regular.tint(Color.accentColor.opacity(0.7)) : (landscape ? .regular.tint(.white.opacity(0.2)) : .regular),
                             in: .circle)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                .offset(x: value.dx * travel, y: -value.dy * travel)
        }
        .frame(width: size, height: size)
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}

/// VoiceOver: a button presses for a moment; the D-pad and the sticks have a direction each.
private struct PadAccessibilityActions: ViewModifier {
    let control: PadControl
    let model: OnScreenGamepadModel

    func body(content: Content) -> some View {
        switch control.kind {
        case .button(let bits):
            content.accessibilityAction { model.pulse(buttons: bits) }
        case .dpad:
            content
                .accessibilityAction(named: "Up") { model.pulse(buttons: PadBits.up) }
                .accessibilityAction(named: "Down") { model.pulse(buttons: PadBits.down) }
                .accessibilityAction(named: "Left") { model.pulse(buttons: PadBits.left) }
                .accessibilityAction(named: "Right") { model.pulse(buttons: PadBits.right) }
        case .stick(let left):
            content
                .accessibilityAction(named: "Up") { push(left, CGVector(dx: 0, dy: 1)) }
                .accessibilityAction(named: "Down") { push(left, CGVector(dx: 0, dy: -1)) }
                .accessibilityAction(named: "Left") { push(left, CGVector(dx: -1, dy: 0)) }
                .accessibilityAction(named: "Right") { push(left, CGVector(dx: 1, dy: 0)) }
        }
    }

    private func push(_ left: Bool, _ direction: CGVector) {
        if left { model.pulse(left: direction) } else { model.pulse(right: direction) }
    }
}

/// A plus: the D-pad (RetroPlay's PadPrimitives).
private struct PlusShape: Shape {
    var armThickness: CGFloat

    func path(in rect: CGRect) -> Path {
        let thickness = min(armThickness, rect.width, rect.height)
        let radius = thickness * 0.22
        var path = Path()
        path.addRoundedRect(in: CGRect(x: rect.midX - thickness / 2, y: rect.minY, width: thickness, height: rect.height),
                            cornerSize: CGSize(width: radius, height: radius))
        path.addRoundedRect(in: CGRect(x: rect.minX, y: rect.midY - thickness / 2, width: rect.width, height: thickness),
                            cornerSize: CGSize(width: radius, height: radius))
        return path
    }
}

// MARK: - Touches

/// Every touch on the pad (RetroPlay's PadTouchView): any number of fingers at once; a thumb
/// slides between buttons and holds both in the gap; a D-pad or stick touch keeps steering
/// off its edge; a slightly missed tap goes to the nearest control; a new press ticks.
final class PadTouchView: UIView {
    weak var model: OnScreenGamepadModel?
    var controls: [PadControl] = [] {
        didSet { if controls != oldValue { dropLostTracks() } }
    }

    /// Reach around each control, in points.
    private let slop: CGFloat = 12
    /// Round buttons are hit a little outside their circle, so neighbours overlap (both held).
    private let buttonReach: CGFloat = 1.12
    /// Stick travel ignored around where the thumb landed (0–1 of full tilt).
    static let deadzone: CGFloat = 0.1

    private enum Track {
        case buttons(UInt32)
        case dpad(id: String, bits: UInt32)
        case stick(id: String, left: Bool, origin: CGPoint, value: CGVector)
    }

    private var tracks: [ObjectIdentifier: Track] = [:]
    private var lastButtons: UInt32 = 0
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Only touches on (or near) a control are the pad's.
    func claims(_ point: CGPoint) -> Bool {
        nearest(to: point) != nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        haptics.prepare()
        for touch in touches {
            let point = touch.location(in: self)
            guard let control = nearest(to: point) else { continue }
            let key = ObjectIdentifier(touch)
            switch control.kind {
            case .button:
                tracks[key] = .buttons(buttonBits(at: point, fallback: control))
            case .dpad:
                tracks[key] = .dpad(id: control.id, bits: dpadBits(control, point))
            case .stick(let left):
                // Zero where the thumb lands; the tilt is measured from there
                tracks[key] = .stick(id: control.id, left: left, origin: point, value: .zero)
            }
        }
        emit()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            guard let track = tracks[key] else { continue }
            let point = touch.location(in: self)
            switch track {
            case .buttons(let old):
                // Slide between buttons; keep the press while the thumb crosses a gap
                let bits = buttonBits(at: point, fallback: nil)
                tracks[key] = .buttons(bits == 0 && nearButton(point) ? old : bits)
            case .dpad(let id, _):
                guard let control = controls.first(where: { $0.id == id }) else { continue }
                tracks[key] = .dpad(id: id, bits: dpadBits(control, point))
            case .stick(let id, let left, var origin, _):
                guard let control = controls.first(where: { $0.id == id }) else { continue }
                let radius = max(36, control.frame.width * 0.38)
                // Past the rim the centre follows the thumb, so turning back answers at once
                var dx = point.x - origin.x, dy = point.y - origin.y
                let distance = hypot(dx, dy)
                if distance > radius {
                    origin.x += dx / distance * (distance - radius)
                    origin.y += dy / distance * (distance - radius)
                    dx = point.x - origin.x
                    dy = point.y - origin.y
                }
                tracks[key] = .stick(id: id, left: left, origin: origin, value: Self.stickValue(dx: dx, dy: dy, radius: radius))
            }
        }
        emit()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            tracks[ObjectIdentifier(touch)] = nil
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

    func forgetTouches() {
        tracks.removeAll()
        emit()
    }

    /// −1…1 with up positive; the dead zone is taken out so the tilt starts smoothly from it.
    static func stickValue(dx: CGFloat, dy: CGFloat, radius: CGFloat) -> CGVector {
        let x = dx / radius, y = -dy / radius
        let magnitude = hypot(x, y)
        guard magnitude > deadzone else { return .zero }
        let scaled = (min(magnitude, 1) - deadzone) / (1 - deadzone)
        return CGVector(dx: x / magnitude * scaled, dy: y / magnitude * scaled)
    }

    // MARK: Geometry

    /// Controls that went away (a new layout) let go of their touches.
    private func dropLostTracks() {
        for (key, track) in tracks {
            switch track {
            case .dpad(let id, _), .stick(let id, _, _, _):
                if !controls.contains(where: { $0.id == id }) { tracks[key] = nil }
            case .buttons:
                break
            }
        }
        DispatchQueue.main.async { [weak self] in self?.emit() }
    }

    private func distance(from point: CGPoint, to control: PadControl) -> CGFloat {
        let frame = control.frame
        if control.isRound {
            return max(0, hypot(point.x - frame.midX, point.y - frame.midY) - min(frame.width, frame.height) / 2)
        }
        let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return hypot(dx, dy)
    }

    /// The control under the point, else the closest within reach.
    private func nearest(to point: CGPoint) -> PadControl? {
        var best: PadControl?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for control in controls {
            let distance = distance(from: point, to: control)
            if distance <= slop && distance < bestDistance {
                best = control
                bestDistance = distance
                if distance == 0 { break }
            }
        }
        return best
    }

    private func nearButton(_ point: CGPoint) -> Bool {
        controls.contains { control in
            if case .button = control.kind { return distance(from: point, to: control) <= slop }
            return false
        }
    }

    /// Every button whose (slightly larger) area has the point: two at once in the gap.
    private func buttonBits(at point: CGPoint, fallback: PadControl?) -> UInt32 {
        var bits: UInt32 = 0
        var closest: (bits: UInt32, distance: CGFloat)?
        for control in controls {
            guard case .button(let buttonBits) = control.kind else { continue }
            let frame = control.frame
            let hit = control.isRound
                ? hypot(point.x - frame.midX, point.y - frame.midY) <= min(frame.width, frame.height) / 2 * buttonReach
                : frame.contains(point)
            if hit {
                bits |= buttonBits
            } else {
                let distance = distance(from: point, to: control)
                if distance <= slop, distance < (closest?.distance ?? .greatestFiniteMagnitude) {
                    closest = (buttonBits, distance)
                }
            }
        }
        if bits != 0 { return bits }
        if let closest { return closest.bits }
        if let fallback, case .button(let bits) = fallback.kind { return bits }
        return 0
    }

    /// Eight ways around the centre, with a small dead middle.
    private func dpadBits(_ control: PadControl, _ point: CGPoint) -> UInt32 {
        let dx = point.x - control.frame.midX, dy = point.y - control.frame.midY
        guard hypot(dx, dy) >= control.frame.width * 0.12 else { return 0 }
        let diagonal: CGFloat = 0.42
        var bits: UInt32 = 0
        if dy < 0 && abs(dy) >= abs(dx) * diagonal { bits |= PadBits.up }
        if dy > 0 && abs(dy) >= abs(dx) * diagonal { bits |= PadBits.down }
        if dx < 0 && abs(dx) >= abs(dy) * diagonal { bits |= PadBits.left }
        if dx > 0 && abs(dx) >= abs(dy) * diagonal { bits |= PadBits.right }
        return bits
    }

    // MARK: Output

    private func emit() {
        var state = PadHeld.idle
        for track in tracks.values {
            switch track {
            case .buttons(let bits), .dpad(_, let bits):
                state.buttons |= bits
            case .stick(_, let left, _, let value):
                if left { state.left = value } else { state.right = value }
            }
        }
        if state.buttons & ~lastButtons != 0 {
            haptics.impactOccurred(intensity: 0.7)
        }
        lastButtons = state.buttons
        model?.setTouched(state)
    }
}
