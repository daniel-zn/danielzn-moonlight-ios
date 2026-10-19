//
//  OnScreenGamepad.swift
//  Artemis
//
//  The on-screen controller (the control bar's controller button): an Xbox-style gamepad of
//  Liquid Glass buttons that the PC sees as an Xbox controller. One layout for both
//  orientations (upright in the trackpad's place, in landscape over the desktop, see-through):
//  a column at each side (the left stick over the D-pad, A B X Y over the right stick), the
//  shoulders above them with the stick clicks outside, Select / Xbox / Start at the bottom centre.
//  Adapted from RetroPlay's pad (Controls/PadControls.swift, PadTouchSurface.swift; the sticks and
//  the D-pad are its PSP pad's): SwiftUI draws the controls, one UIKit view takes every touch on
//  them, so several fingers work at once (a stick, a trigger and a face button), a thumb slides
//  between face buttons, and a new press ticks a haptic. Touches away from the controls fall
//  through to the desktop.
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

    var isRound: Bool {
        switch look {
        case .face, .click, .guide, .stick: true
        default: false
        }
    }
}

enum PadBits {
    static let a = UInt32(A_FLAG), b = UInt32(B_FLAG), x = UInt32(X_FLAG), y = UInt32(Y_FLAG)
    static let up = UInt32(UP_FLAG), down = UInt32(DOWN_FLAG), left = UInt32(LEFT_FLAG), right = UInt32(RIGHT_FLAG)
    static let lb = UInt32(LB_FLAG), rb = UInt32(RB_FLAG)
    /// Select is the Xbox controller's Back (View) button, Start its Start (Menu) button.
    static let select = UInt32(BACK_FLAG), start = UInt32(PLAY_FLAG), guide = UInt32(SPECIAL_FLAG)
    static let leftClick = UInt32(LS_CLK_FLAG), rightClick = UInt32(RS_CLK_FLAG)
    /// The triggers ride along as bits of their own (Moonlight's flags don't use these) and go
    /// out as fully pulled.
    static let leftTrigger: UInt32 = 1 << 30
    static let rightTrigger: UInt32 = 1 << 31
    static let triggers = leftTrigger | rightTrigger
}

/// RetroPlay's PSP colours: the sticks' and the D-pad's tints on the plain background.
enum PadPalette {
    static let dpad = Color(red: 0.18, green: 0.18, blue: 0.20)
    static let gate = Color(red: 0.16, green: 0.16, blue: 0.17)
    static let nub = Color(red: 0.32, green: 0.32, blue: 0.34)
}

enum PadLayout {
    /// Settings › Controllers › On-screen controller size: a share of the full size (Large),
    /// which shrinks further where the space is too small for it.
    static let sizes: [(name: String, scale: Double)] = [("Small", 0.8), ("Medium", 0.9), ("Large", 1)]
    static let defaultSize = 0.9

    private static let xbox = (a: Color(red: 0.36, green: 0.72, blue: 0.26), b: Color(red: 0.86, green: 0.24, blue: 0.22),
                               x: Color(red: 0.20, green: 0.50, blue: 0.95), y: Color(red: 0.95, green: 0.74, blue: 0.10))

    // The full size, in points: RetroPlay's PSP pad at Large (its stick and D-pad, its diamond's spacing)
    static let stick: CGFloat = 122
    static let dpad: CGFloat = 144
    static let faceDiameter: CGFloat = 54
    static let faceReach = faceDiameter * 0.9
    private static let faceSpan = faceReach * 2 + faceDiameter
    private static let column = max(stick, dpad, faceSpan)
    /// The columns' rows: the left stick beside A B X Y, the D-pad beside the right stick.
    private static let topRow = max(stick, faceSpan), bottomRow = max(dpad, stick), rowGap: CGFloat = 10
    private static let columnHeight = topRow + rowGap + bottomRow
    private static let shoulder = CGSize(width: 64, height: 40), click: CGFloat = 40, shoulderGap: CGFloat = 6
    /// L3, LT, LB (and mirrored RB, RT, R3).
    private static let shoulderGroup = click + shoulder.width * 2 + shoulderGap * 2
    private static let pill = CGSize(width: 58, height: 30), guide: CGFloat = 44, middleGap: CGFloat = 14
    private static let middleRow = pill.width * 2 + guide + middleGap * 2
    /// Between the shoulders and the columns, the columns and Select / Xbox / Start below them.
    private static let gap: CGFloat = 12

    /// The controls in `area` (upright, the trackpad's place; in landscape, the safe area). The
    /// columns go at its sides and the shoulders at its top corners; Select / Xbox / Start at its
    /// bottom centre, between the columns when it's wide, under them when it's tall.
    static func controls(in area: CGRect, scale: Double) -> [PadControl] {
        let unit = unit(in: area, scale: scale)
        let beside = isWide(area)
        func size(_ value: CGFloat) -> CGFloat { value * unit }

        // The shoulders along the top: L3 LT LB at the left corner, RB RT R3 mirrored
        let top = area.minY
        func leftShoulder(_ x: CGFloat, _ width: CGFloat) -> CGRect {
            CGRect(x: area.minX + size(x), y: top, width: size(width), height: size(shoulder.height))
        }
        func rightShoulder(_ x: CGFloat, _ width: CGFloat) -> CGRect {
            CGRect(x: area.maxX - size(x + width), y: top, width: size(width), height: size(shoulder.height))
        }
        let lt = click + shoulderGap, lb = lt + shoulder.width + shoulderGap

        // Select / Xbox / Start at the bottom centre
        let middleY = area.maxY - size(guide) / 2
        let guideFrame = CGRect(x: area.midX - size(guide) / 2, y: middleY - size(guide) / 2, width: size(guide), height: size(guide))
        let pillY = middleY - size(pill.height) / 2
        let select = CGRect(x: guideFrame.minX - size(middleGap + pill.width), y: pillY, width: size(pill.width), height: size(pill.height))
        let start = CGRect(x: guideFrame.maxX + size(middleGap), y: pillY, width: size(pill.width), height: size(pill.height))

        // The columns, centred in what's left between the shoulders and the bottom (or the row)
        let columnsTop = top + size(shoulder.height + gap)
        let columnsBottom = beside ? area.maxY : guideFrame.minY - size(gap)
        let y0 = columnsTop + max(0, (columnsBottom - columnsTop - size(columnHeight)) / 2)
        let upper = y0 + size(topRow) / 2, lower = y0 + size(topRow + rowGap) + size(bottomRow) / 2
        let leftX = area.minX + size(column) / 2, rightX = area.maxX - size(column) / 2
        func round(_ x: CGFloat, _ y: CGFloat, _ diameter: CGFloat) -> CGRect {
            CGRect(x: x - size(diameter) / 2, y: y - size(diameter) / 2, width: size(diameter), height: size(diameter))
        }

        return [stickClick(left: true, round(area.minX + size(click) / 2, top + size(shoulder.height) / 2, click)),
                PadControl(id: "LT", title: "LT", accessibility: "Left Trigger", kind: .button(PadBits.leftTrigger), look: .shoulder,
                           frame: leftShoulder(lt, shoulder.width)),
                PadControl(id: "LB", title: "LB", accessibility: "Left Bumper", kind: .button(PadBits.lb), look: .shoulder,
                           frame: leftShoulder(lb, shoulder.width)),
                PadControl(id: "RB", title: "RB", accessibility: "Right Bumper", kind: .button(PadBits.rb), look: .shoulder,
                           frame: rightShoulder(lb, shoulder.width)),
                PadControl(id: "RT", title: "RT", accessibility: "Right Trigger", kind: .button(PadBits.rightTrigger), look: .shoulder,
                           frame: rightShoulder(lt, shoulder.width)),
                stickClick(left: false, round(area.maxX - size(click) / 2, top + size(shoulder.height) / 2, click)),
                PadControl(id: "Select", title: "Select", accessibility: "Select", kind: .button(PadBits.select), look: .pill, frame: select),
                PadControl(id: "Guide", title: "", accessibility: "Xbox Button", kind: .button(PadBits.guide), look: .guide, frame: guideFrame),
                PadControl(id: "Start", title: "Start", accessibility: "Start", kind: .button(PadBits.start), look: .pill, frame: start),
                stick(left: true, round(leftX, upper, stick))]
            + face(center: CGPoint(x: rightX, y: upper), diameter: size(faceDiameter), reach: size(faceReach))
            + [PadControl(id: "dpad", title: "", accessibility: "D-pad", kind: .dpad, look: .dpad, frame: round(leftX, lower, dpad)),
               stick(left: false, round(rightX, lower, stick))]
    }

    /// Where the control bar goes while the pad lies over the desktop (landscape), as a fraction
    /// of the screen: top centre between the shoulders, or under them if it doesn't fit there.
    static func barCenter(area: CGRect, bounds: CGSize, barSize: CGSize, scale: Double) -> CGPoint {
        let unit = unit(in: area, scale: scale)
        let between = area.width - 2 * shoulderGroup * unit
        let y = between >= barSize.width + 16
            ? area.minY + shoulder.height * unit / 2
            : area.minY + (shoulder.height + gap) * unit + barSize.height / 2
        return CGPoint(x: area.midX / bounds.width, y: y / bounds.height)
    }

    private static func isWide(_ area: CGRect) -> Bool {
        area.width > area.height
    }

    /// Points per design point: the full size where it fits, times the size setting.
    private static func unit(in area: CGRect, scale: Double) -> CGFloat {
        let width = max(2 * shoulderGroup + gap, 2 * column + (isWide(area) ? middleRow + 2 * gap : gap))
        let height = shoulder.height + gap + columnHeight + (isWide(area) ? 0 : gap + guide)
        return max(0.4, min(area.width / width, area.height / height, 1) * min(scale, 1))
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

    private static func stickClick(left: Bool, _ frame: CGRect) -> PadControl {
        PadControl(id: left ? "L3" : "R3", title: left ? "L3" : "R3", accessibility: left ? "Left Stick Click" : "Right Stick Click",
                   kind: .button(left ? PadBits.leftClick : PadBits.rightClick), look: .click, frame: frame)
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
    /// Lying over the desktop (landscape): clear glass, so the picture shows.
    var overDesktop = false
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

    /// Lays the controls out in `area` (in the view's coordinates); `overDesktop` in landscape.
    func layout(area: CGRect, overDesktop: Bool, scale: Double, opacity: Double) {
        host.view.frame = bounds
        touchView.frame = bounds
        let controls = PadLayout.controls(in: area, scale: scale)
        if model.controls != controls { model.controls = controls }
        if model.overDesktop != overDesktop { model.overDesktop = overDesktop }
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
            case .face(let color): round(Text(control.title).font(label(control.frame.width * 0.4)), tint: color)
            case .shoulder: flat(shape: RoundedRectangle(cornerRadius: control.frame.height * 0.32, style: .continuous))
            case .pill: flat(shape: Capsule())
            case .click: round(Text(control.title).font(label(control.frame.width * 0.36)), tint: nil)
            case .guide: round(Image(systemName: "xbox.logo").font(.system(size: control.frame.width * 0.48, weight: .medium)), tint: nil)
            case .dpad: dpad
            case .stick: stick
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(control.accessibility)
        .accessibilityIdentifier("pad.\(control.id)")
        .modifier(PadAccessibilityActions(control: control, model: model))
    }

    private var overDesktop: Bool { model.overDesktop }

    private var bits: UInt32 {
        if case .button(let bits) = control.kind { return bits }
        return 0
    }

    private func label(_ size: CGFloat) -> Font {
        .custom(Typography.postScriptName, fixedSize: size)
    }

    /// Over the desktop the glass is clear (a little darkened so it reads over white windows),
    /// so the picture shows; on the plain background upright it's tinted dark, as RetroPlay's
    /// PSP pad. The labels are light on both.
    private func glass(tint: Color?, held: Bool) -> Glass {
        if held { return .regular.tint((tint ?? .accentColor).opacity(0.85)) }
        if overDesktop { return tint.map { .clear.tint($0.opacity(0.25)) } ?? .clear.tint(.black.opacity(0.22)) }
        return .regular.tint((tint ?? PadPalette.nub).opacity(0.8))
    }

    /// A, B, X, Y (their colour on the label over the desktop), L3, R3 and the Xbox button.
    private func round<Label: View>(_ label: Label, tint: Color?) -> some View {
        let held = model.isHeld(bits)
        let diameter = control.frame.width
        return label
            .foregroundStyle(overDesktop && !held ? tint ?? .white : .white)
            .shadow(color: .black.opacity(overDesktop ? 0.5 : 0), radius: 2)
            .frame(width: diameter, height: diameter)
            .glassEffect(glass(tint: tint, held: held), in: .circle)
            .scaleEffect(held ? 0.92 : 1)
            .animation(.easeOut(duration: 0.06), value: held)
            .accessibilityAddTraits(.isButton)
    }

    private func flat<S: Shape>(shape: S) -> some View {
        let held = model.isHeld(bits)
        return Text(control.title)
            .font(label(min(control.frame.height * 0.42, 17)))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(overDesktop ? 0.5 : 0), radius: 2)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 4)
            .frame(width: control.frame.width, height: control.frame.height)
            .glassEffect(glass(tint: nil, held: held), in: shape)
            .scaleEffect(held ? 0.95 : 1)
            .animation(.easeOut(duration: 0.06), value: held)
            .accessibilityAddTraits(.isButton)
    }

    /// RetroPlay's PadDPad (the PSP's colours): clear glass over the desktop.
    private var dpad: some View {
        let size = control.frame.width
        let arm = size * 0.36
        let travel = (size - arm) / 2
        return ZStack {
            Color.clear.glassEffect(overDesktop ? .clear : .regular.tint(PadPalette.dpad.opacity(0.8)), in: PlusShape(armThickness: arm))
            ForEach([(PadBits.up, "arrowtriangle.up.fill", CGSize(width: 0, height: -travel)),
                     (PadBits.down, "arrowtriangle.down.fill", CGSize(width: 0, height: travel)),
                     (PadBits.left, "arrowtriangle.left.fill", CGSize(width: -travel, height: 0)),
                     (PadBits.right, "arrowtriangle.right.fill", CGSize(width: travel, height: 0))], id: \.0) { bits, symbol, offset in
                let held = model.isHeld(bits)
                ZStack {
                    RoundedRectangle(cornerRadius: arm * 0.2, style: .continuous)
                        .fill(PadPalette.nub.opacity(held ? 1 : 0))
                        .frame(width: arm * 0.86, height: arm * 0.86)
                    Image(systemName: symbol)
                        .font(.system(size: max(8, arm * 0.24), weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.78).opacity(held ? 1 : 0.5))
                }
                .offset(offset)
                .animation(.easeOut(duration: 0.06), value: held)
            }
            Circle()
                .fill(Color.black.opacity(0.25))
                .frame(width: arm * 0.42, height: arm * 0.42)
        }
        .frame(width: size, height: size)
        .accessibilityAddTraits(.isButton)
    }

    /// RetroPlay's PadStick as on its PSP pad (round, not octagonal): the knob goes where the
    /// thumb is, clear glass over the desktop.
    private var stick: some View {
        let size = control.frame.width
        let travel = size * PadTouchView.stickTravelFraction
        let left = control.kind == .stick(left: true)
        let value = left ? model.held.left : model.held.right
        return ZStack {
            Color.clear.glassEffect(overDesktop ? .clear : .regular.tint(PadPalette.gate.opacity(0.8)), in: .circle)
            Color.clear
                .frame(width: size * 0.46, height: size * 0.46)
                .glassEffect(overDesktop ? .clear : .regular.tint(PadPalette.nub.opacity(0.8)), in: .circle)
                .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
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
/// off its edge; a slightly missed tap goes to the nearest control; a new press ticks (a
/// button or a D-pad direction; a stick doesn't).
final class PadTouchView: UIView {
    weak var model: OnScreenGamepadModel?
    var controls: [PadControl] = [] {
        didSet { if controls != oldValue { dropLostTracks() } }
    }

    /// Reach around each control, in points.
    private let slop: CGFloat = 14
    /// Round buttons are hit a little outside their circle, so neighbours overlap (both held).
    private let buttonReach: CGFloat = 1.12
    /// How far a stick's knob moves from its centre at full tilt, as a share of its size.
    static let stickTravelFraction: CGFloat = 0.30
    /// How far the thumb moves for full tilt: three quarters of the knob's travel (RetroPlay's
    /// `PadStick.touchTravelFraction`: a thumb's touch point sits a little inside where it feels
    /// it's pressing, so at 1:1 a full push often read as 70–80 %). Past it, full tilt.
    static let stickTouchFraction: CGFloat = stickTravelFraction * 0.75

    private enum Track {
        case buttons(UInt32)
        case dpad(id: String, bits: UInt32)
        case stick(id: String, left: Bool, stick: TouchStick, value: CGVector)
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
                // The stick's centre is zero, and the knob goes where the thumb is
                let stick = TouchStick(originX: control.frame.midX, originY: control.frame.midY,
                                       radius: min(control.frame.width, control.frame.height) * Self.stickTouchFraction)
                tracks[key] = .stick(id: control.id, left: left, stick: stick, value: Self.value(stick, point))
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
            case .stick(let id, let left, let stick, _):
                tracks[key] = .stick(id: id, left: left, stick: stick, value: Self.value(stick, point))
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

    /// −1…1 with up positive (RetroPlay's TouchStick: an 8 % dead zone, taken out smoothly).
    private static func value(_ stick: TouchStick, _ point: CGPoint) -> CGVector {
        let value = stick.update(x: point.x, y: point.y)
        return CGVector(dx: value.x, dy: value.y)
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

    /// Eight ways around the centre, with a small dead middle (RetroPlay's D-pad).
    private func dpadBits(_ control: PadControl, _ point: CGPoint) -> UInt32 {
        let size = Double(min(control.frame.width, control.frame.height))
        let directions = PadHitTesting.dpad(dx: point.x - control.frame.midX, dy: point.y - control.frame.midY,
                                            deadzone: size * 0.12, diagonalRatio: 0.42)
        var bits: UInt32 = 0
        if directions.up { bits |= PadBits.up }
        if directions.down { bits |= PadBits.down }
        if directions.left { bits |= PadBits.left }
        if directions.right { bits |= PadBits.right }
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
