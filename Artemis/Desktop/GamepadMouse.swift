//
//  GamepadMouse.swift
//  Artemis
//
//  A game controller as the PC's mouse, as in the Mac app (moonlight-qt's gamepad mouse):
//  hold Start / Menu on its own for 0.75 s to turn it on or off. While on, the controller's
//  state isn't sent to the PC as a gamepad (it's sent at rest once as the mouse turns on). Left stick: pointer; right stick: scroll; A / B / X: left,
//  right, middle click; LB / RB: back / forward; D-pad: one scroll step; Y: the keyboard.
//  Settings › Controllers › Mouse control with a controller turns the long press on.
//

import QuartzCore
import UIKit

/// Where the controller's mouse input goes (DesktopViewController).
protocol GamepadMouseOutput: AnyObject {
    /// Moves the pointer by desktop pixels.
    func gamepadMouseMove(dx: CGFloat, dy: CGFloat)
    func gamepadMouseButton(_ button: Int32, down: Bool)
    /// High-resolution amounts (120 = one notch); positive scrolls up / right.
    func gamepadMouseScroll(vertical: Int, horizontal: Int)
    func gamepadMouseToggleKeyboard()
    func gamepadMouseChanged(active: Bool)
}

@objc(ArtemisGamepadMouse)
final class GamepadMouse: NSObject, ArtemisGamepadFilter {
    static let longPress: TimeInterval = 0.75
    /// Stick travel ignored around the centre (0–1).
    static let deadzone = 0.15
    /// Desktop pixels per second at full tilt, at pointer speed 1×.
    static let pointerSpeed = 1500.0
    /// Scroll units per second at full tilt (12 notches).
    static let scrollSpeed = 1440.0

    weak var output: GamepadMouseOutput?
    /// The setting: whether holding Start turns the mouse on.
    var enabled: Bool
    /// Settings › Touch & Pointer › Pointer speed.
    var speed: Double = 1
    /// The clock, and whether a display link moves the pointer (the demo script ticks by itself).
    var now: () -> TimeInterval = { CACurrentMediaTime() }
    var drivesItself = true
    /// Runs the output calls the controller's states cause. Later on the main queue: the filter
    /// is called with ControllerSupport's locks held (the demo script delivers at once).
    var deliver: (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }

    /// The controller driving the mouse, when on. Also read off the main thread (old MFi
    /// controllers' Start), hence the lock.
    private var activeIndex: Int?
    private let activeLock = NSLock()
    private(set) var activeController: Int? {
        get { activeLock.withLock { activeIndex } }
        set { activeLock.withLock { activeIndex = newValue } }
    }
    var isActive: Bool { activeController != nil }

    /// When Start went down, for each controller; nil once another button joined it (a combo
    /// like Start+Select isn't a long press of Start).
    private var startPressedAt: [Int: TimeInterval?] = [:]
    private var lastButtons: UInt32 = 0
    private var left = CGVector.zero
    private var right = CGVector.zero
    private var pointerRemainder = CGVector.zero
    private var scrollRemainder = CGVector.zero
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0

    init(enabled: Bool) {
        self.enabled = enabled
        super.init()
    }

    deinit {
        link?.invalidate()
    }

    // MARK: ArtemisGamepadFilter

    func filterController(_ index: Int, buttons: UInt32, leftStickX: Int16, leftStickY: Int16,
                          rightStickX: Int16, rightStickY: Int16) -> ArtemisGamepadFilterResult {
        // Old MFi controllers' Start comes from a background thread: just keep it from the PC
        // while the mouse is on (those can't toggle it: their Start is too short)
        guard Thread.isMainThread else { return activeController == index ? .withhold : .send }

        let wasActive = activeController == index
        let start = buttons & UInt32(PLAY_FLAG) != 0
        let others = buttons & ~UInt32(PLAY_FLAG) != 0
        if start {
            if startPressedAt[index] == nil {
                startPressedAt[index] = others ? .some(nil) : now()
            } else if others {
                startPressedAt[index] = .some(nil)
            }
        } else if let entry = startPressedAt.removeValue(forKey: index), let pressedAt = entry,
                  !others, now() - pressedAt >= Self.longPress {
            if activeController == index {
                deactivate()
            } else if enabled && activeController == nil {
                activate(index, buttons: buttons)
            }
        }

        guard activeController == index else { return .send }
        // Just turned on: the PC gets the controller at rest, so nothing stays held there
        guard wasActive else { return .sendNeutral }

        let pressed = buttons & ~lastButtons
        let released = lastButtons & ~buttons
        lastButtons = buttons
        deliver { [weak self] in
            guard let output = self?.output else { return }
            for (flag, button) in Self.buttonMapping {
                if pressed & UInt32(flag) != 0 { output.gamepadMouseButton(button, down: true) }
                if released & UInt32(flag) != 0 { output.gamepadMouseButton(button, down: false) }
            }
            if pressed & UInt32(UP_FLAG) != 0 { output.gamepadMouseScroll(vertical: 120, horizontal: 0) }
            if pressed & UInt32(DOWN_FLAG) != 0 { output.gamepadMouseScroll(vertical: -120, horizontal: 0) }
            if pressed & UInt32(RIGHT_FLAG) != 0 { output.gamepadMouseScroll(vertical: 0, horizontal: 120) }
            if pressed & UInt32(LEFT_FLAG) != 0 { output.gamepadMouseScroll(vertical: 0, horizontal: -120) }
            if pressed & UInt32(Y_FLAG) != 0 { output.gamepadMouseToggleKeyboard() }
        }

        left = Self.stick(leftStickX, leftStickY)
        right = Self.stick(rightStickX, rightStickY)
        updateLink()
        return .withhold
    }

    private static let buttonMapping: [(Int32, Int32)] = [(A_FLAG, BUTTON_LEFT), (B_FLAG, BUTTON_RIGHT), (X_FLAG, BUTTON_MIDDLE),
                                                          (LB_FLAG, BUTTON_X1), (RB_FLAG, BUTTON_X2)]

    func controllerDisconnected(_ index: Int) {
        startPressedAt[index] = nil
        if activeController == index { deactivate() }
    }

    /// The session is ending.
    func stop() {
        if isActive { deactivate() }
        startPressedAt.removeAll()
    }

    // MARK: Movement

    /// Moves and scrolls for `interval` seconds of the sticks' current tilt.
    func tick(_ interval: TimeInterval) {
        guard isActive else { return }
        let dt = CGFloat(min(interval, 0.1))
        let pointerScale = CGFloat(Self.pointerSpeed * speed) * dt
        pointerRemainder.dx += left.dx * pointerScale
        // Stick up is positive; the desktop's y grows downward
        pointerRemainder.dy -= left.dy * pointerScale
        if abs(pointerRemainder.dx) >= 1 || abs(pointerRemainder.dy) >= 1 {
            let dx = pointerRemainder.dx.rounded(.towardZero), dy = pointerRemainder.dy.rounded(.towardZero)
            pointerRemainder.dx -= dx
            pointerRemainder.dy -= dy
            output?.gamepadMouseMove(dx: dx, dy: dy)
        }
        let scrollScale = CGFloat(Self.scrollSpeed) * dt
        scrollRemainder.dx += right.dx * scrollScale
        scrollRemainder.dy += right.dy * scrollScale
        // In steps of 30 (a quarter notch), so the PC isn't flooded
        let vertical = Int(scrollRemainder.dy / 30) * 30, horizontal = Int(scrollRemainder.dx / 30) * 30
        if vertical != 0 || horizontal != 0 {
            scrollRemainder.dy -= CGFloat(vertical)
            scrollRemainder.dx -= CGFloat(horizontal)
            output?.gamepadMouseScroll(vertical: vertical, horizontal: horizontal)
        }
    }

    /// A stick's tilt past the dead zone, squared for fine control near the centre (0–1 each way).
    static func stick(_ x: Int16, _ y: Int16) -> CGVector {
        let vector = CGVector(dx: Double(x) / 32767, dy: Double(y) / 32767)
        let magnitude = min(hypot(vector.dx, vector.dy), 1)
        guard magnitude > deadzone else { return .zero }
        let scaled = (magnitude - deadzone) / (1 - deadzone)
        let factor = scaled * scaled / magnitude
        return CGVector(dx: vector.dx * factor, dy: vector.dy * factor)
    }

    // MARK: On and off

    private func activate(_ index: Int, buttons: UInt32) {
        activeController = index
        lastButtons = buttons
        left = .zero
        right = .zero
        pointerRemainder = .zero
        scrollRemainder = .zero
        deliver { [weak self] in self?.output?.gamepadMouseChanged(active: true) }
    }

    private func deactivate() {
        // Nothing stays held on the PC
        let held = lastButtons
        activeController = nil
        lastButtons = 0
        left = .zero
        right = .zero
        updateLink()
        deliver { [weak self] in
            guard let output = self?.output else { return }
            for (flag, button) in Self.buttonMapping where held & UInt32(flag) != 0 {
                output.gamepadMouseButton(button, down: false)
            }
            output.gamepadMouseChanged(active: false)
        }
    }

    private func updateLink() {
        let moving = isActive && (left != .zero || right != .zero)
        if moving && drivesItself && link == nil {
            let link = CADisplayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
            lastTick = CACurrentMediaTime()
        } else if !moving, let link {
            link.invalidate()
            self.link = nil
        }
    }

    @objc private func step(_ link: CADisplayLink) {
        let time = link.timestamp
        tick(time - lastTick)
        lastTick = time
    }
}
