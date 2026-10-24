// SPDX-License-Identifier: GPL-3.0-or-later
//
//  PadHitTesting.swift
//  Artemis
//
//  RetroPlay's pad geometry, RetroPlayCore/Play/PadHitTesting.swift, copied as it is (less
//  `public`), so the on-screen controller's D-pad and sticks answer exactly as RetroPlay's PSP
//  pad. Scripts/pad-parity checks the copy still matches.
//

import Foundation

/// Geometry helpers for on-screen pads. UI views map gestures through these so
/// D-pad / stick / DS touch behavior stays testable without SwiftUI.
enum PadHitTesting {
    /// Four-way (+ optional diagonals) from a touch offset in view space (Y down).
    /// `diagonalRatio` is how much the weaker axis must match the stronger to count
    /// (0.38 ≈ generous diagonals, still ignores near-axis jitter).
    static func dpad(
        dx: Double,
        dy: Double,
        deadzone: Double = 10,
        diagonalRatio: Double = 0.38
    ) -> (up: Bool, down: Bool, left: Bool, right: Bool) {
        let mag = (dx * dx + dy * dy).squareRoot()
        if mag < deadzone {
            return (false, false, false, false)
        }
        let ax = abs(dx)
        let ay = abs(dy)
        let up = dy < 0 && ay >= ax * diagonalRatio
        let down = dy > 0 && ay >= ax * diagonalRatio
        let left = dx < 0 && ax >= ay * diagonalRatio
        let right = dx > 0 && ax >= ay * diagonalRatio
        return (up, down, left, right)
    }

    /// Analog stick sample. View space (Y down) → stick space (Y up).
    /// Clamped to a unit circle, then scaled to `maxMagnitude` (N64 digital scaffold used ±80).
    static func analog(
        dx: Double,
        dy: Double,
        radius: Double,
        maxMagnitude: Int8 = 80,
        deadzone: Double = 0.12
    ) -> (x: Int8, y: Int8) {
        guard radius > 0 else { return (0, 0) }
        var nx = dx / radius
        var ny = -dy / radius
        let mag = (nx * nx + ny * ny).squareRoot()
        if mag < deadzone {
            return (0, 0)
        }
        if mag > 1 {
            nx /= mag
            ny /= mag
        }
        let scale = Double(maxMagnitude)
        return (
            Int8(clamping: Int((nx * scale).rounded())),
            Int8(clamping: Int((ny * scale).rounded()))
        )
    }

    /// Analog stick as −1…1 per axis (Y up-positive), clamped to the unit circle.
    /// The deadzone is rescaled away so small deflections still start from zero smoothly.
    static func analogUnit(
        dx: Double,
        dy: Double,
        radius: Double,
        deadzone: Double = 0.1
    ) -> (x: Double, y: Double) {
        guard radius > 0 else { return (0, 0) }
        let nx = dx / radius
        let ny = -dy / radius
        let mag = (nx * nx + ny * ny).squareRoot()
        guard mag > deadzone else { return (0, 0) }
        let clamped = min(mag, 1)
        let scaled = (clamped - deadzone) / (1 - deadzone)
        return (nx / mag * scaled, ny / mag * scaled)
    }

    /// Map a point inside a view to NDS bottom-screen pixels (256×192).
    static func ndsTouch(
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) -> (x: UInt16, y: UInt16) {
        guard width > 0, height > 0 else { return (0, 0) }
        let nx = min(1, max(0, x / width))
        let ny = min(1, max(0, y / height))
        return (UInt16((nx * 255).rounded(.down)), UInt16((ny * 191).rounded(.down)))
    }
}

/// On-screen analog stick that measures from where the thumb *landed*, not from the
/// centre of the graphic. A thumb that lands off-centre therefore starts at zero, and
/// small movements give small deflections (true analog). If the thumb overshoots the
/// travel radius, the origin is dragged along behind it, so reversing direction takes
/// one radius of movement instead of crossing the whole well.
struct TouchStick: Sendable, Equatable {
    let originX: Double
    let originY: Double
    /// Thumb travel for full deflection, in points.
    let radius: Double
    /// Fraction of `radius` that reads as zero (thumb wobble).
    let deadzone: Double

    init(originX: Double, originY: Double, radius: Double, deadzone: Double = 0.08) {
        self.originX = originX
        self.originY = originY
        self.radius = max(1, radius)
        self.deadzone = min(max(deadzone, 0), 0.9)
    }

    /// Feed the current touch point (view space, Y down). Returns −1…1, Y up-positive.
    /// The centre stays where the thumb landed: past the rim the stick holds full tilt toward
    /// the thumb, and it only eases back once the thumb is back over the stick's travel.
    mutating func update(x: Double, y: Double) -> (x: Double, y: Double) {
        PadHitTesting.analogUnit(dx: x - originX, dy: y - originY, radius: radius, deadzone: deadzone)
    }
}

