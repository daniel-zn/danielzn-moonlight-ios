// SPDX-License-Identifier: GPL-3.0-or-later
// Feeds RetroPlay's PSP stick / D-pad and Artemis's the same touch traces and checks every step
// gives the same normalized values (bit for bit), then maps Artemis's to the Xbox stick range.

import Foundation
import CoreGraphics
import RP
import AR

typealias Event = (finger: Int, phase: Int, x: CGFloat, y: CGFloat)
let began = 0, moved = 1, ended = 2

/// Straight line from a to b in `steps` moves (not counting a).
func line(_ finger: Int, _ a: CGPoint, _ b: CGPoint, steps: Int) -> [Event] {
    (1...steps).map { i in
        let t = CGFloat(i) / CGFloat(steps)
        return (finger, moved, a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
    }
}

var failures = 0
var csv = ["size,trace,step,finger,phase,x,y,retroplay_x,retroplay_y,retroplay_buttons,artemis_x,artemis_y,artemis_buttons,xbox_x,xbox_y"]

@MainActor
func run(size: CGFloat) {
    // RetroPlay's PSP column: D-pad above, stick below; a face button off to the right
    let stick = CGRect(x: 40, y: 330, width: size, height: size)
    let dpadSize = size * 144 / 122
    let dpad = CGRect(x: 40 + (size - dpadSize) / 2, y: 330 - 10 - dpadSize, width: dpadSize, height: dpadSize)
    let button = CGRect(x: 300, y: 300, width: 54, height: 54)
    let c = CGPoint(x: stick.midX, y: stick.midY)
    let r = size * 0.30 * 0.75
    func at(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: c.x + dx * r, y: c.y + dy * r) }
    func tap(_ f: Int, _ p: CGPoint) -> Event { (f, began, p.x, p.y) }
    func up(_ f: Int) -> Event { (f, ended, 0, 0) }

    var traces: [(String, [Event])] = []
    traces.append(("centre, slow drag right past the rim, lift",
                   [tap(0, c)] + line(0, c, at(1.3, 0), steps: 60) + [up(0)]))
    traces.append(("off-centre start, slow diagonal drag, lift",
                   [tap(0, at(0.5, -0.3))] + line(0, at(0.5, -0.3), at(-0.4, 0.6), steps: 40) + [up(0)]))
    traces.append(("flick from the centre to the edge, lift",
                   [tap(0, c)] + line(0, c, at(0, 2), steps: 3) + [up(0)]))
    traces.append(("slide off the stick and back, lift",
                   [tap(0, at(0.2, 0.1))] + line(0, at(0.2, 0.1), at(2.5, 0), steps: 20)
                   + line(0, at(2.5, 0), CGPoint(x: c.x + size * 1.5, y: c.y - size), steps: 20)
                   + line(0, CGPoint(x: c.x + size * 1.5, y: c.y - size), at(-0.2, 0.1), steps: 30) + [up(0)]))
    traces.append(("lands just outside the well, within reach",
                   [tap(0, CGPoint(x: c.x - size / 2 - 10, y: c.y))] + line(0, CGPoint(x: c.x - size / 2 - 10, y: c.y), c, steps: 15) + [up(0)]))
    traces.append(("lands out of reach: nothing",
                   [tap(0, CGPoint(x: c.x, y: stick.maxY + 20))] + line(0, CGPoint(x: c.x, y: stick.maxY + 20), c, steps: 5) + [up(0)]))
    var circle: [Event] = [tap(0, at(0.5, 0))]
    for degrees in stride(from: 0, through: 720, by: 7) {
        let a = CGFloat(degrees) * .pi / 180
        let k = 0.2 + 1.4 * CGFloat(degrees) / 720
        circle.append((0, moved, c.x + cos(a) * k * r, c.y + sin(a) * k * r))
    }
    traces.append(("spiral out past the rim", circle + [up(0)]))
    traces.append(("stick + D-pad + button at once, lifting in turn",
                   [tap(0, at(0.3, 0.3)), tap(1, CGPoint(x: dpad.midX, y: dpad.minY + 8)), tap(2, CGPoint(x: button.midX, y: button.midY))]
                   + line(0, at(0.3, 0.3), at(-1, -1), steps: 10)
                   + line(1, CGPoint(x: dpad.midX, y: dpad.minY + 8), CGPoint(x: dpad.maxX + 30, y: dpad.maxY + 30), steps: 12)
                   + [up(2)] + line(0, at(-1, -1), at(0.05, 0), steps: 6) + [up(0), up(1)]))
    // (Two thumbs on the one stick isn't compared: both apps keep every touch in a dictionary
    // and take whichever thumb comes last in it, which differs from run to run.)
    // The D-pad: a tap on every point of a grid over it and around it, then a sweep around its
    // centre that keeps steering off the edge
    var grid: [Event] = []
    for gx in stride(from: dpad.minX - 20, through: dpad.maxX + 20, by: 6) {
        for gy in stride(from: dpad.minY - 20, through: dpad.maxY + 20, by: 6) {
            grid += [tap(0, CGPoint(x: gx, y: gy)), up(0)]
        }
    }
    traces.append(("D-pad grid taps", grid))
    var sweep: [Event] = [tap(0, CGPoint(x: dpad.midX, y: dpad.midY))]
    for degrees in stride(from: 0, through: 1080, by: 3) {
        let a = CGFloat(degrees) * .pi / 180
        let k = dpadSize * (0.05 + 0.9 * CGFloat(degrees) / 1080)
        sweep.append((0, moved, dpad.midX + cos(a) * k, dpad.midY + sin(a) * k))
    }
    traces.append(("D-pad sweep out past the edge", sweep + [up(0)]))

    var steps = 0
    for (name, events) in traces {
        let a = retroPlayTrace(stick: stick, dpad: dpad, button: button, events: events)
        let b = artemisTrace(stick: stick, dpad: dpad, button: button, events: events)
        for (i, event) in events.enumerated() {
            steps += 1
            let xbox = (artemisXbox(Float(b[i][0])), artemisXbox(Float(b[i][1])))
            csv.append("\(size),\(name),\(i),\(event.finger),\(event.phase),\(event.x),\(event.y),\(a[i][0]),\(a[i][1]),\(Int(a[i][2])),\(b[i][0]),\(b[i][1]),\(Int(b[i][2])),\(xbox.0),\(xbox.1)")
            if a[i] != b[i] {
                failures += 1
                if failures <= 20 { print("DIFF size \(size) \(name) step \(i): RetroPlay \(a[i]) Artemis \(b[i])") }
            }
            // The same value from RetroPlay maps to the same Xbox axis
            if artemisXbox(Float(a[i][0])) != xbox.0 || artemisXbox(Float(a[i][1])) != xbox.1 { failures += 1 }
        }
        let peak = a.map { hypot($0[0], $0[1]) }.max() ?? 0
        print(String(format: "size %5.1f  %-50@ %4d steps  same: %@  peak tilt %.3f", size, name as NSString, events.count,
                     a == b ? "yes" : "NO", peak))
    }
    print("size \(size): \(steps) steps compared")
}

MainActor.assumeIsolated {
    // RetroPlay's PSP stick: compact (108), full size (122), on an iPhone 17 Pro (122 × 1.088),
    // and whatever Artemis lays out in between
    for size in [108, 122, 132.8, 117.3] as [CGFloat] { run(size: size) }
}

// Xbox range: full tilt reaches each end, rest is zero
let ends: [(Float, Int16)] = [(1, 32767), (-1, -32768), (0, 0), (1.5, 32767), (-1.5, -32768), (0.5, 16384), (-0.5, -16384)]
for (value, expected) in ends where artemisXbox(value) != expected {
    failures += 1
    print("Xbox axis for \(value): \(artemisXbox(value)), expected \(expected)")
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "pad-parity.csv"
try? csv.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
print("\(csv.count - 1) rows in \(out)")
print(failures == 0 ? "PASS: RetroPlay's and Artemis's sticks and D-pads gave identical values at every step" : "FAIL: \(failures) differences")
exit(failures == 0 ? 0 : 1)
