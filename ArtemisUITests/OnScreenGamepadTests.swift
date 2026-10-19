//
//  OnScreenGamepadTests.swift
//  ArtemisUITests
//
//  The connected screen's layout and the on-screen controller (docs/TOUCH.md) against the
//  demo desktop, which records what would go to the PC: "gamepad connect", then each state as
//  "gamepad <buttons> lt <0–255> rt <0–255> ls <x> <y> rs <x> <y>" (sticks −32767…32767, up
//  positive), and "gamepad disconnect".
//

import XCTest

final class OnScreenGamepadTests: XCTestCase {
    private var appearance: String {
        ProcessInfo.processInfo.environment["ARTEMIS_APPEARANCE"].flatMap { $0.isEmpty ? nil : $0 } ?? "system"
    }

    override func setUp() {
        continueAfterFailure = true
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    /// Upright: the trackpad has no click buttons and the bar sits under it; system gestures
    /// aren't deferred; the bar has no right click, and its controller button swaps the
    /// trackpad for the gamepad, whose buttons and sticks reach the PC as a controller.
    func testGamepadUpright() {
        let tag = "\(appearance)-portrait-L-gamepad"
        let (app, desktop) = connect(orientation: .portrait)
        XCTAssertTrue(status(desktop).contains("edges none"), "\(tag): system gestures deferred (\(status(desktop)))")

        let trackpad = app.otherElements["trackpad"].firstMatch
        let bar = app.buttons["bar.keyboard"]
        XCTAssertTrue(trackpad.exists, "\(tag): no trackpad")
        XCTAssertFalse(app.buttons["trackpad.left"].exists, "\(tag): the trackpad still has a left button")
        XCTAssertFalse(app.buttons["trackpad.right"].exists, "\(tag): the trackpad still has a right button")
        XCTAssertFalse(app.buttons["bar.rightClick"].exists, "\(tag): the bar still has a right click")
        XCTAssertGreaterThan(bar.frame.minY, trackpad.frame.maxY, "\(tag): the bar isn't under the trackpad")
        XCTAssertGreaterThan(trackpad.frame.minY, desktop.frame.maxY - 1, "\(tag): the trackpad isn't under the desktop")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(bar.frame.maxY, window.maxY - 140, "\(tag): the bar isn't at the bottom")
        shot("\(tag)-1-trackpad")

        // The controller: in the trackpad's place
        var count = state(desktop).count
        let toggle = app.buttons["bar.gamepad"]
        XCTAssertTrue(toggle.exists, "\(tag): no controller button")
        toggle.tap()
        let a = app.buttons["pad.A"]
        XCTAssertTrue(a.waitForExistence(timeout: 5), "\(tag): no gamepad")
        sleep(1)
        XCTAssertFalse(app.otherElements["trackpad"].firstMatch.exists, "\(tag): the trackpad is still there")
        XCTAssertEqual(events(desktop, since: count).first, "gamepad connect", "\(tag): \(events(desktop, since: count))")
        for id in ["pad.A", "pad.B", "pad.X", "pad.Y", "pad.LB", "pad.RB", "pad.LT", "pad.RT", "pad.View", "pad.Menu",
                   "pad.Guide", "pad.dpad", "pad.leftStick", "pad.rightStick"] {
            let element = control(app, id)
            XCTAssertTrue(element.exists, "\(tag): no \(id)")
            XCTAssertGreaterThan(element.frame.minY, desktop.frame.maxY - 1, "\(tag): \(id) over the desktop")
            XCTAssertLessThan(element.frame.maxY, bar.frame.minY + 1, "\(tag): \(id) under the bar")
            XCTAssertGreaterThanOrEqual(element.frame.minX, window.minX, "\(tag): \(id) off screen")
            XCTAssertLessThanOrEqual(element.frame.maxX, window.maxX, "\(tag): \(id) off screen")
        }
        shot("\(tag)-2-shown")
        controls(app, desktop, tag: tag)

        // Off again: the PC's controller goes away, the trackpad comes back
        count = state(desktop).count
        toggle.tap()
        sleep(1)
        XCTAssertFalse(app.buttons["pad.A"].exists, "\(tag): the gamepad didn't hide")
        XCTAssertEqual(events(desktop, since: count).last, "gamepad disconnect", "\(tag): \(events(desktop, since: count))")
        XCTAssertTrue(app.otherElements["trackpad"].firstMatch.waitForExistence(timeout: 3), "\(tag): no trackpad after")
        app.terminate()
    }

    /// Landscape: the gamepad lies over the desktop; touches away from its controls still
    /// move the pointer, touches on them don't.
    func testGamepadLandscape() {
        let tag = "\(appearance)-landscape-L-gamepad"
        let (app, desktop) = connect(orientation: .landscapeLeft)
        XCTAssertTrue(status(desktop).contains("edges none"), "\(tag): system gestures deferred (\(status(desktop)))")
        XCTAssertFalse(app.buttons["bar.rightClick"].exists, "\(tag): the bar still has a right click")
        app.buttons["bar.gamepad"].tap()
        XCTAssertTrue(app.buttons["pad.A"].waitForExistence(timeout: 5), "\(tag): no gamepad")
        sleep(1)
        let screen = desktop.frame
        for id in ["pad.A", "pad.LT", "pad.RT", "pad.dpad", "pad.leftStick", "pad.rightStick", "pad.Menu"] {
            let element = control(app, id)
            XCTAssertTrue(element.exists, "\(tag): no \(id)")
            XCTAssertTrue(screen.contains(element.frame), "\(tag): \(id) not over the desktop (\(element.frame) in \(screen))")
        }
        XCTAssertTrue(app.buttons["bar.keyboard"].isHittable, "\(tag): the bar is covered")
        shot("\(tag)-1-shown")
        controls(app, desktop, tag: tag)

        // The desktop between the controls: still the trackpad
        let count = state(desktop).count
        // Slowly, so a busy machine still delivers several moves
        point(desktop, 0.45, 0.45).press(forDuration: 0.05, thenDragTo: point(desktop, 0.6, 0.45), withVelocity: 150,
                                         thenHoldForDuration: 0.1)
        let new = events(desktop, since: count)
        XCTAssertGreaterThan(new.filter { $0.hasPrefix("move ") }.count, 2, "\(tag): the desktop didn't move the pointer (\(new))")
        XCTAssertFalse(new.contains { $0.hasPrefix("gamepad") }, "\(tag): the desktop drag pressed the gamepad (\(new))")

        // Disconnect with the gamepad up: one tap ends the session
        app.buttons["bar.disconnect"].tap()
        XCTAssertTrue(app.buttons["game.Desktop"].waitForExistence(timeout: 10), "\(tag): one tap on Disconnect didn't return to the apps")
        app.terminate()
    }

    /// Daniel's large text: the bar, with the controller button, still fits; the gamepad too.
    func testGamepadLargeText() {
        for (orientation, name) in [(UIDeviceOrientation.portrait, "portrait"), (.landscapeLeft, "landscape")] {
            let tag = "\(appearance)-\(name)-AX5-gamepad"
            let (app, _) = connect(size: "UICTContentSizeCategoryAccessibilityXXXL", orientation: orientation)
            let window = app.windows.firstMatch.frame
            app.buttons["bar.gamepad"].tap()
            XCTAssertTrue(app.buttons["pad.A"].waitForExistence(timeout: 5), "\(tag): no gamepad")
            sleep(1)
            for id in ["bar.keyboard", "bar.gamepad", "bar.disconnect", "pad.A", "pad.LT", "pad.RT", "pad.Menu"] {
                let element = control(app, id)
                XCTAssertTrue(element.exists, "\(tag): no \(id)")
                XCTAssertTrue(window.contains(element.frame), "\(tag): \(id) off screen")
            }
            shot("\(tag)-1-shown")
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
    }

    // MARK: Controls

    /// A, a trigger, the sticks, the D-pad, and several at once.
    private func controls(_ app: XCUIApplication, _ desktop: XCUIElement, tag: String) {
        // A: down and up, nothing else
        var count = state(desktop).count
        app.buttons["pad.A"].tap()
        sleep(1)
        var new = events(desktop, since: count)
        XCTAssertEqual(new, ["gamepad 0x1000 lt 0 rt 0 ls 0 0 rs 0 0", "gamepad 0x0000 lt 0 rt 0 ls 0 0 rs 0 0"], "\(tag) A: \(new)")

        // The right trigger: fully pulled while held
        count = state(desktop).count
        app.buttons["pad.RT"].press(forDuration: 0.3)
        sleep(1)
        new = events(desktop, since: count)
        XCTAssertEqual(new, ["gamepad 0x0000 lt 0 rt 255 ls 0 0 rs 0 0", "gamepad 0x0000 lt 0 rt 0 ls 0 0 rs 0 0"], "\(tag) RT: \(new)")

        // Guide and Menu
        count = state(desktop).count
        app.buttons["pad.Guide"].tap()
        app.buttons["pad.Menu"].tap()
        sleep(1)
        new = events(desktop, since: count)
        XCTAssertEqual(new.filter { !$0.hasPrefix("gamepad 0x0000") }, ["gamepad 0x0400 lt 0 rt 0 ls 0 0 rs 0 0", "gamepad 0x0010 lt 0 rt 0 ls 0 0 rs 0 0"],
                       "\(tag) Guide, Menu: \(new)")

        // The D-pad's top: up
        count = state(desktop).count
        let dpad = control(app, "pad.dpad")
        dpad.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        sleep(1)
        new = events(desktop, since: count)
        XCTAssertEqual(new.first, "gamepad 0x0001 lt 0 rt 0 ls 0 0 rs 0 0", "\(tag) D-pad up: \(new)")
        XCTAssertEqual(new.last, "gamepad 0x0000 lt 0 rt 0 ls 0 0 rs 0 0", "\(tag) D-pad up: \(new)")

        // The left stick pushed right: x up to full, y about 0, back to the centre on release; the
        // right stick pushed up
        for (id, label) in [("pad.leftStick", "ls"), ("pad.rightStick", "rs")] {
            count = state(desktop).count
            let stick = control(app, id)
            let push = id == "pad.leftStick" ? CGVector(dx: 0.5 + 1.2, dy: 0.5) : CGVector(dx: 0.5, dy: 0.5 - 1.2)
            stick.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: stick.coordinate(withNormalizedOffset: push), withVelocity: 300, thenHoldForDuration: 0.3)
            sleep(1)
            new = events(desktop, since: count)
            let values = new.compactMap { stickValue($0, label) }
            XCTAssertTrue(values.contains { id == "pad.leftStick" ? $0.x > 30000 && abs($0.y) < 3000 : $0.y > 30000 && abs($0.x) < 3000 },
                          "\(tag) \(id): \(new)")
            XCTAssertEqual(values.last.map { [$0.x, $0.y] }, [0, 0], "\(tag) \(id) didn't return to the centre: \(new)")
            XCTAssertFalse(new.contains { $0.hasPrefix("move ") }, "\(tag) \(id) moved the pointer: \(new)")
        }

        // Several at once: A held, the left stick pushed left and the left trigger pulled
        count = state(desktop).count
        let aCenter = center(app.buttons["pad.A"])
        let stickCenter = center(control(app, "pad.leftStick"))
        let ltCenter = center(app.buttons["pad.LT"])
        // The fingers go down and lift together (the synthesizer mixes up fingers that start at
        // different times); the stick's waits, then moves
        XCTAssertTrue(MultiTouch.timed([(aCenter, .zero, 0, 1.0, 0), (ltCenter, .zero, 0, 1.0, 0),
                                        (stickCenter, CGVector(dx: -70, dy: 0), 0, 0.7, 0.3)], testCase: self),
                      "\(tag): couldn't synthesize several fingers")
        sleep(1)
        new = events(desktop, since: count)
        let together = new.contains { event in
            guard event.hasPrefix("gamepad 0x1000 lt 255"), let stick = stickValue(event, "ls") else { return false }
            return stick.x < -20000
        }
        XCTAssertTrue(together, "\(tag) A + LT + stick at once: \(new)")
        XCTAssertEqual(new.last, "gamepad 0x0000 lt 0 rt 0 ls 0 0 rs 0 0", "\(tag) several: not all released \(new)")
        XCTAssertFalse(new.contains { $0.hasPrefix("move ") || $0.hasPrefix("down ") }, "\(tag) several: mouse input \(new)")
        shot("\(tag)-3-after-controls")
    }

    // MARK: Helpers

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["ARTEMIS_SHOT_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private func connect(size: String = "UICTContentSizeCategoryL", orientation: UIDeviceOrientation) -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments = ["-ArtemisDemo", "YES", "-UIPreferredContentSizeCategoryName", size,
                               "-ArtemisShowControlBar", "YES", "-ArtemisBarCenter", "{0.5, 0.92}"]
        app.launch()
        XCUIDevice.shared.orientation = orientation
        let enchilada = app.buttons["computer.ENCHILADA"]
        XCTAssertTrue(enchilada.waitForExistence(timeout: 15))
        enchilada.tap()
        let desktopApp = app.buttons["game.Desktop"]
        XCTAssertTrue(desktopApp.waitForExistence(timeout: 10))
        desktopApp.tap()
        let desktop = app.otherElements["desktop"]
        XCTAssertTrue(desktop.waitForExistence(timeout: 10), "the desktop didn't open")
        sleep(1)
        return (app, desktop)
    }

    private func control(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func center(_ element: XCUIElement) -> CGPoint {
        CGPoint(x: element.frame.midX, y: element.frame.midY)
    }

    private func point(_ desktop: XCUIElement, _ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        desktop.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    private func status(_ desktop: XCUIElement) -> String {
        state(desktop).status
    }

    private func state(_ desktop: XCUIElement) -> (status: String, count: Int, events: [String]) {
        let lines = (desktop.value as? String ?? "").components(separatedBy: "\n")
        let count = lines.dropFirst().first.flatMap { Int($0.replacingOccurrences(of: "events ", with: "")) } ?? 0
        return (lines.first ?? "", count, Array(lines.dropFirst(2)))
    }

    private func events(_ desktop: XCUIElement, since count: Int) -> [String] {
        let now = state(desktop)
        let new = now.count - count
        return new <= 0 ? [] : Array(now.events.suffix(min(new, now.events.count)))
    }

    /// A stick's x and y in a gamepad event ("ls" or "rs").
    private func stickValue(_ event: String, _ label: String) -> (x: Int, y: Int)? {
        let words = event.split(separator: " ").map(String.init)
        guard words.first == "gamepad", let index = words.firstIndex(of: label), index + 2 < words.count,
              let x = Int(words[index + 1]), let y = Int(words[index + 2]) else { return nil }
        return (x, y)
    }
}
