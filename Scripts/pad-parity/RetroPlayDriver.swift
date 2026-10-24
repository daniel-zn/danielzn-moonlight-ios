// SPDX-License-Identifier: GPL-3.0-or-later
// Appended to a copy of RetroPlay's PadTouchSurface.swift (same file, so it reaches the touch
// view's private began / moved / emit): plays a trace on RetroPlay's PSP stick and D-pad.

@available(iOS 18.0, *)
@MainActor
public func retroPlayTrace(stick: CGRect, dpad: CGRect, button: CGRect,
                           events: [(finger: Int, phase: Int, x: CGFloat, y: CGFloat)]) -> [[Double]] {
    PadTouchView.parityTrace(stick: stick, dpad: dpad, button: button, events: events)
}

@available(iOS 18.0, *)
extension PadTouchView {
  static func parityTrace(stick: CGRect, dpad: CGRect, button: CGRect,
                          events: [(finger: Int, phase: Int, x: CGFloat, y: CGFloat)]) -> [[Double]] {
    let view = PadTouchView()
    view.hapticsEnabled = false
    view.regions = [
        PadRegion(id: "button.1024", kind: .button(1024), frame: button, shape: .circle),
        PadRegion(id: "dpad.1", kind: .dpad(up: 1, down: 2, left: 4, right: 8), frame: dpad, shape: .rect),
        PadRegion(id: "stick", kind: .stick, frame: stick, shape: .circle),
    ]
    var last = PadTouchOutput.idle
    view.onChange = { last = $0 }
    let fingers = (0..<10).map { _ in NSObject() }
    var rows: [[Double]] = []
    for event in events {
        let key = ObjectIdentifier(fingers[event.finger])
        let p = CGPoint(x: event.x, y: event.y)
        switch event.phase {
        case 0: view.began(key, at: p)
        case 1: view.moved(key, to: p)
        default: view.tracks[key] = nil
        }
        view.emit()
        rows.append([Double(last.stickX), Double(last.stickY), Double(last.buttons)])
    }
    return rows
}
}
