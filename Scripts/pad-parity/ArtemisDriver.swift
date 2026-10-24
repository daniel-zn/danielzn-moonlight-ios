// SPDX-License-Identifier: GPL-3.0-or-later
// Plays a trace on Artemis's left stick and D-pad (Artemis/Desktop/PadTouch.swift).

import SwiftUI
import UIKit

@MainActor
public func artemisTrace(stick: CGRect, dpad: CGRect, button: CGRect,
                         events: [(finger: Int, phase: Int, x: CGFloat, y: CGFloat)]) -> [[Double]] {
    let view = PadTouchView()
    view.hapticsEnabled = false
    view.controls = [
        PadControl(id: "A", title: "A", accessibility: "A", kind: .button(1024), look: .face(.green), frame: button),
        PadControl(id: "dpad", title: "", accessibility: "D-pad", kind: .dpad(up: 1, down: 2, left: 4, right: 8), look: .dpad, frame: dpad),
        PadControl(id: "leftStick", title: "", accessibility: "Left Stick", kind: .stick(left: true), look: .stick, frame: stick),
    ]
    var last = PadHeld.idle
    view.onChange = { last = $0 }
    let fingers = (0..<10).map { _ in NSObject() }
    var rows: [[Double]] = []
    for event in events {
        let key = ObjectIdentifier(fingers[event.finger])
        let p = CGPoint(x: event.x, y: event.y)
        switch event.phase {
        case 0: view.began(key, at: p)
        case 1: view.moved(key, to: p)
        default: view.ended(key)
        }
        view.touchesMoved([], with: nil)  // emit, as after each touch event
        rows.append([Double(last.leftX), Double(last.leftY), Double(last.buttons)])
    }
    return rows
}

/// Artemis's stick value as the PC gets it.
public func artemisXbox(_ value: Float) -> Int16 { PadHeld.xboxAxis(value) }
