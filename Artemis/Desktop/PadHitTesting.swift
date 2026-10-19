// SPDX-License-Identifier: GPL-3.0-or-later
//
//  PadHitTesting.swift
//  Artemis
//
//  RetroPlay's pad geometry (RetroPlayCore/Play/PadHitTesting.swift, the D-pad and analog stick
//  parts), so the on-screen controller's D-pad and sticks answer exactly as RetroPlay's PSP pad.
//

import Foundation

/// Geometry helpers for on-screen pads. UI views map gestures through these so
/// D-pad / stick behavior stays testable without SwiftUI.
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
}

/// An on-screen analog stick: its centre is zero and the knob goes where the thumb is; past
/// the rim it holds full tilt toward the thumb, and it eases back once the thumb is back over
/// the stick's travel.
struct TouchStick: Equatable {
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
    func update(x: Double, y: Double) -> (x: Double, y: Double) {
        PadHitTesting.analogUnit(dx: x - originX, dy: y - originY, radius: radius, deadzone: deadzone)
    }
}
