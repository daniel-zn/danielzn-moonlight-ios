//
//  DesktopTests.swift
//  ArtemisUITests
//
//  The remote desktop's touch controls (docs/TOUCH.md) against the demo desktop
//  (-ArtemisDemo YES), which records the input events the gestures produce in the desktop's
//  accessibility value. Each gesture is checked for its events, upright and in landscape,
//  with screenshots of the connected screen, the control bar, the key row and the zoom.
//

import XCTest

final class DesktopTests: XCTestCase {
    private var appearance: String {
        ProcessInfo.processInfo.environment["ARTEMIS_APPEARANCE"].flatMap { $0.isEmpty ? nil : $0 } ?? "system"
    }

    override func setUp() {
        continueAfterFailure = true
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    func testGesturesUpright() { gestures(orientation: .portrait, name: "portrait") }
    func testGesturesLandscape() { gestures(orientation: .landscapeLeft, name: "landscape") }
    func testLargeTextUpright() { largeText(orientation: .portrait, name: "portrait") }
    func testLargeTextLandscape() { largeText(orientation: .landscapeLeft, name: "landscape") }

    /// Windows' sign-in screen takes only key events, not Unicode text: a password typed on the
    /// iOS keyboard, or typed from the clipboard, goes as keys (Shift for capitals and "!").
    func testTypedPassword() {
        let tag = "\(appearance)-portrait-L-password"
        let (app, desktop) = connect(orientation: .portrait)
        let video = videoFrame(desktop)
        XCTAssertTrue(MultiTouch.drag(fingers: [CGPoint(x: video.midX - 40, y: video.midY), CGPoint(x: video.midX, y: video.midY),
                                                CGPoint(x: video.midX + 40, y: video.midY)], by: .zero, duration: 0.1, testCase: self))
        XCTAssertTrue(app.buttons["key.Esc"].waitForExistence(timeout: 5), "\(tag): the three-finger tap didn't open the keyboard")
        let password = ["key 0x50 +shift", "key 0x41", "key 0x35", "key 0x35", "key 0x57", "key 0x4F", "key 0x52", "key 0x44",
                        "key 0x31 +shift"]

        var count = state(desktop).count
        typeKeys(app, "Pa55word!")
        shot("\(tag)-1-typed")
        XCTAssertEqual(events(desktop, since: count), password, "\(tag) typed")

        // Type Clipboard, from the shortcuts menu (iOS asks before the app reads the clipboard)
        UIPasteboard.general.string = "Pa55word!"
        count = state(desktop).count
        app.buttons["bar.shortcuts"].tap()
        let typeClipboard = app.buttons["Type Clipboard"].firstMatch
        XCTAssertTrue(typeClipboard.waitForExistence(timeout: 5), "\(tag): no Type Clipboard")
        typeClipboard.tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow Paste"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        sleep(1)
        XCTAssertEqual(events(desktop, since: count), password, "\(tag) clipboard")
        app.terminate()
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

    /// Opens the demo PC's active Desktop app: the connected screen.
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

    /// The desktop's state line and its recorded events.
    private func state(_ desktop: XCUIElement) -> (status: String, count: Int, events: [String]) {
        let lines = (desktop.value as? String ?? "").components(separatedBy: "\n")
        let count = lines.dropFirst().first.flatMap { Int($0.replacingOccurrences(of: "events ", with: "")) } ?? 0
        return (lines.first ?? "", count, Array(lines.dropFirst(2)))
    }

    /// The events recorded since `count`.
    private func events(_ desktop: XCUIElement, since count: Int) -> [String] {
        let now = state(desktop)
        let new = now.count - count
        return new <= 0 ? [] : Array(now.events.suffix(min(new, now.events.count)))
    }

    private func zoom(_ desktop: XCUIElement) -> Double {
        let status = state(desktop).status
        guard let range = status.range(of: #"zoom ([0-9.]+)"#, options: .regularExpression) else { return 0 }
        return Double(status[range].replacingOccurrences(of: "zoom ", with: "")) ?? 0
    }

    private func point(_ desktop: XCUIElement, _ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        desktop.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    /// The desktop picture's rectangle on screen (the canvas letterboxes it to 16:9).
    private func videoFrame(_ desktop: XCUIElement) -> CGRect {
        let frame = desktop.frame
        var size = CGSize(width: frame.width, height: frame.width * 9 / 16)
        if size.height > frame.height { size = CGSize(width: frame.height * 16 / 9, height: frame.height) }
        return CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func moves(_ events: [String]) -> [(Int, Int)] {
        events.compactMap { event in
            let parts = event.split(separator: " ")
            guard parts.count == 3, parts[0] == "move", let x = Int(parts[1]), let y = Int(parts[2]) else { return nil }
            return (x, y)
        }
    }

    /// Types on the iOS keyboard's keys (the desktop's key capture isn't a text field, so
    /// typeText has no focused element to type into): Shift for a capital, the 123 layer for
    /// digits and punctuation.
    private func typeKeys(_ app: XCUIApplication, _ text: String) {
        let keyboard = app.keyboards.firstMatch
        for character in text {
            let key = keyboard.keys[String(character)]
            if !key.waitForExistence(timeout: 1) {
                if character.isUppercase {
                    keyboard.buttons["shift"].tap()
                } else {
                    // Letters ↔ numbers and punctuation
                    keyboard.keys["more"].tap()
                }
            }
            if key.waitForExistence(timeout: 3) {
                key.tap()
            } else {
                app.typeText(String(character))
            }
        }
    }

    private func disconnectMenuItem(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Disconnect", "bar.disconnect")).firstMatch
    }

    // MARK: Gestures

    private func gestures(orientation: UIDeviceOrientation, name: String) {
        let tag = "\(appearance)-\(name)-L-desktop"
        let (app, desktop) = connect(orientation: orientation)
        XCTAssertTrue(state(desktop).status.contains("trackpad"), "\(tag): doesn't start in trackpad mode (\(state(desktop).status))")
        XCTAssertTrue(app.buttons["bar.keyboard"].exists, "\(tag): no control bar")
        if orientation == .portrait {
            XCTAssertTrue(app.otherElements["trackpad"].exists || app.buttons["trackpad.left"].exists, "\(tag): no trackpad area upright")
            XCTAssertLessThan(desktop.frame.maxY, app.buttons["bar.keyboard"].frame.minY + 1, "\(tag): the bar covers the desktop")
        }
        shot("\(tag)-1-connected")

        // One finger drag: the pointer moves right, without clicking
        var count = state(desktop).count
        point(desktop, 0.4, 0.5).press(forDuration: 0.05, thenDragTo: point(desktop, 0.7, 0.5))
        var new = events(desktop, since: count)
        let moved = moves(new)
        XCTAssertGreaterThan(moved.count, 2, "\(tag) drag: no pointer moves (\(new))")
        if let first = moved.first, let last = moved.last {
            XCTAssertGreaterThan(last.0, first.0, "\(tag) drag: the pointer didn't move right (\(moved))")
        }
        XCTAssertFalse(new.contains("down left"), "\(tag) drag: it clicked (\(new))")

        // Tap: a left click (the release follows a moment later)
        count = state(desktop).count
        point(desktop, 0.5, 0.5).tap()
        sleep(1)
        new = events(desktop, since: count)
        XCTAssertEqual(new.filter { $0.hasSuffix("left") }, ["down left", "up left"], "\(tag) tap: \(new)")

        // Press and hold, then drag: a left drag
        count = state(desktop).count
        point(desktop, 0.5, 0.5).press(forDuration: 0.9, thenDragTo: point(desktop, 0.3, 0.4))
        sleep(1)
        new = events(desktop, since: count)
        XCTAssertEqual(new.first { $0.hasSuffix("left") }, "down left", "\(tag) hold-drag: \(new)")
        XCTAssertEqual(new.last { $0.hasSuffix("left") }, "up left", "\(tag) hold-drag: \(new)")
        if let down = new.firstIndex(of: "down left"), let up = new.lastIndex(of: "up left") {
            XCTAssertFalse(moves(Array(new[down..<up])).isEmpty, "\(tag) hold-drag: no moves while held (\(new))")
        }

        // Tap, then touch again and drag (moving only after the tap's release would have come):
        // one left drag, the button held from the tap to the end of the drag
        count = state(desktop).count
        let video0 = videoFrame(desktop)
        XCTAssertTrue(MultiTouch.tapThenDrag(at: CGPoint(x: video0.midX, y: video0.midY), by: CGVector(dx: 70, dy: 20),
                                             gap: 0.12, hold: 0.2, testCase: self))
        sleep(1)
        new = events(desktop, since: count)
        XCTAssertEqual(new.filter { $0.hasSuffix("left") }, ["down left", "up left"], "\(tag) tap-drag: \(new)")
        if let down = new.firstIndex(of: "down left"), let up = new.lastIndex(of: "up left") {
            XCTAssertGreaterThan(moves(Array(new[down..<up])).count, 2, "\(tag) tap-drag: no moves while held (\(new))")
        }

        // Press and hold without moving: a right click
        count = state(desktop).count
        point(desktop, 0.5, 0.5).press(forDuration: 0.9)
        sleep(1)
        new = events(desktop, since: count)
        XCTAssertEqual(new.filter { $0.hasSuffix("right") }, ["down right", "up right"], "\(tag) hold: \(new)")

        // Two-finger tap: a right click
        count = state(desktop).count
        let video = videoFrame(desktop)
        XCTAssertTrue(MultiTouch.drag(fingers: [CGPoint(x: video.midX - 30, y: video.midY), CGPoint(x: video.midX + 30, y: video.midY)],
                                      by: .zero, duration: 0.08, testCase: self), "\(tag): couldn't synthesize two fingers")
        sleep(1)
        new = events(desktop, since: count)
        XCTAssertEqual(new.filter { $0.hasSuffix("right") }, ["down right", "up right"], "\(tag) two-finger tap: \(new)")

        // Two-finger drag: scroll (natural: fingers down scrolls up, positive)
        count = state(desktop).count
        XCTAssertTrue(MultiTouch.drag(fingers: [CGPoint(x: video.midX - 30, y: video.midY - 40), CGPoint(x: video.midX + 30, y: video.midY - 40)],
                                      by: CGVector(dx: 0, dy: 80), duration: 0.5, testCase: self), "\(tag): couldn't synthesize two fingers")
        sleep(2)
        new = events(desktop, since: count)
        let scrolls = new.filter { $0.hasPrefix("scroll") }
        XCTAssertFalse(scrolls.isEmpty, "\(tag) two-finger drag: no scroll (\(new))")
        let vertical = scrolls.compactMap { Int($0.split(separator: " ")[1]) }.reduce(0, +)
        XCTAssertGreaterThan(vertical, 120, "\(tag) two-finger drag: scrolled \(vertical) (\(scrolls.prefix(5)))")
        XCTAssertTrue(moves(new).isEmpty, "\(tag) two-finger drag moved the pointer (\(new))")

        // Pinch: zooms the view; the bar offers to reset it
        let spread = min(video.width, video.height) * 0.3
        XCTAssertTrue(MultiTouch.paths([(CGPoint(x: video.midX - 20, y: video.midY), CGVector(dx: -spread, dy: 0)),
                                        (CGPoint(x: video.midX + 20, y: video.midY), CGVector(dx: spread, dy: 0))],
                                       duration: 0.6, testCase: self))
        sleep(1)
        XCTAssertGreaterThan(zoom(desktop), 1.3, "\(tag) pinch: \(state(desktop).status)")
        let reset = app.buttons["bar.resetZoom"]
        XCTAssertTrue(reset.waitForExistence(timeout: 3), "\(tag): no reset zoom button")
        shot("\(tag)-2-zoomed")
        // Three-finger drag pans the zoomed view without input
        count = state(desktop).count
        _ = MultiTouch.drag(fingers: [CGPoint(x: video.midX - 40, y: video.midY), CGPoint(x: video.midX, y: video.midY),
                                      CGPoint(x: video.midX + 40, y: video.midY)], by: CGVector(dx: 60, dy: 0), duration: 0.4, testCase: self)
        sleep(1)
        XCTAssertTrue(events(desktop, since: count).isEmpty, "\(tag) three-finger pan sent input (\(events(desktop, since: count)))")
        reset.tap()
        sleep(1)
        XCTAssertEqual(zoom(desktop), 1, accuracy: 0.01, "\(tag) reset zoom: \(state(desktop).status)")

        // Three-finger tap: the keyboard
        XCTAssertTrue(MultiTouch.drag(fingers: [CGPoint(x: video.midX - 40, y: video.midY), CGPoint(x: video.midX, y: video.midY),
                                                CGPoint(x: video.midX + 40, y: video.midY)], by: .zero, duration: 0.1, testCase: self))
        XCTAssertTrue(app.buttons["key.Esc"].waitForExistence(timeout: 5), "\(tag): the three-finger tap didn't open the keyboard")
        XCTAssertTrue(state(desktop).status.contains("keyboard on"), "\(tag): \(state(desktop).status)")

        // The key row: Esc, sticky Ctrl + a typed c, F5, typed text
        count = state(desktop).count
        app.buttons["key.Esc"].tap()
        app.buttons["key.Ctrl"].tap()
        XCTAssertEqual(app.buttons["key.Ctrl"].value as? String, "Held", "\(tag): Ctrl isn't held")
        shot("\(tag)-3-keyboard")
        typeKeys(app, "c")
        typeKeys(app, "hi")
        new = events(desktop, since: count)
        XCTAssertEqual(new, ["key 0x1B", "key 0x43 +ctrl", "key 0x48", "key 0x49"], "\(tag) keys: \(new)")
        XCTAssertEqual(app.buttons["key.Ctrl"].value as? String ?? "", "", "\(tag): Ctrl stayed held")
        // A locked modifier stays for several keys
        app.buttons["key.Shift"].doubleTap()
        XCTAssertEqual(app.buttons["key.Shift"].value as? String, "Locked", "\(tag): Shift didn't lock")
        count = state(desktop).count
        app.buttons["key.Left"].tap()
        app.buttons["key.Left"].tap()
        app.buttons["key.Shift"].tap()
        new = events(desktop, since: count)
        XCTAssertEqual(new, ["key 0x25 +shift", "key 0x25 +shift"], "\(tag) locked shift: \(new)")
        app.buttons["key.page"].tap()
        XCTAssertTrue(app.buttons["key.F5"].waitForExistence(timeout: 3), "\(tag): no function keys")
        count = state(desktop).count
        app.buttons["key.F5"].tap()
        XCTAssertEqual(events(desktop, since: count), ["key 0x74"], "\(tag) F5")
        shot("\(tag)-4-function-keys")
        app.buttons["key.page"].tap()
        app.buttons["key.hide"].tap()
        sleep(1)
        XCTAssertTrue(state(desktop).status.contains("keyboard off"), "\(tag): the keyboard didn't hide")

        // Shortcuts
        count = state(desktop).count
        app.buttons["bar.shortcuts"].tap()
        let copy = app.buttons["Copy"].firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "\(tag): no shortcuts menu")
        shot("\(tag)-5-shortcuts")
        copy.tap()
        sleep(1)
        let taskManager = app.buttons["Task Manager"].firstMatch
        // The first tap can land while the menu is still going away
        for _ in 0..<3 where !app.buttons["Windows"].firstMatch.exists {
            app.buttons["bar.shortcuts"].tap()
            _ = app.buttons["Windows"].firstMatch.waitForExistence(timeout: 2)
        }
        app.buttons["Windows"].firstMatch.tap()
        XCTAssertTrue(taskManager.waitForExistence(timeout: 5), "\(tag): no Windows submenu")
        shot("\(tag)-5b-windows-shortcuts")
        taskManager.tap()
        sleep(1)
        new = events(desktop, since: count)
        XCTAssertEqual(new, ["key 0x43 +ctrl", "key 0x1B +ctrl +shift"], "\(tag) shortcuts: \(new)")

        // The bar's right click
        count = state(desktop).count
        app.buttons["bar.rightClick"].tap()
        XCTAssertEqual(events(desktop, since: count), ["down right", "up right"], "\(tag) right click button")

        // Direct mode: a tap clicks where it lands
        app.buttons["bar.mode"].tap()
        XCTAssertTrue(state(desktop).status.contains("direct"), "\(tag): \(state(desktop).status)")
        count = state(desktop).count
        let target = XCUIApplication().coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: video.minX + video.width * 0.25, dy: video.minY + video.height * 0.75))
        target.tap()
        sleep(1)
        new = events(desktop, since: count)
        if let landing = moves(new).last {
            XCTAssertEqual(Double(landing.0), 480, accuracy: 40, "\(tag) direct tap x: \(new)")
            XCTAssertEqual(Double(landing.1), 810, accuracy: 40, "\(tag) direct tap y: \(new)")
        } else {
            XCTFail("\(tag) direct tap: no move (\(new))")
        }
        XCTAssertEqual(new.filter { $0.hasSuffix("left") }, ["down left", "up left"], "\(tag) direct tap: \(new)")
        app.buttons["bar.mode"].tap()

        // Landscape: the bar folds into a button and back
        if orientation != .portrait {
            app.buttons["bar.fold"].tap()
            XCTAssertTrue(app.buttons["bar.unfold"].waitForExistence(timeout: 3) || app.otherElements["bar.unfold"].exists, "\(tag): no folded bar")
            shot("\(tag)-6-folded")
            let unfold = app.buttons["bar.unfold"].exists ? app.buttons["bar.unfold"] : app.otherElements["bar.unfold"]
            unfold.tap()
            XCTAssertTrue(app.buttons["bar.disconnect"].waitForExistence(timeout: 3), "\(tag): the bar didn't unfold")
        }

        // Disconnect: back to the apps
        let item = disconnectMenuItem(app)
        for _ in 0..<3 where !item.exists {
            app.buttons["bar.disconnect"].tap()
            _ = item.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(item.exists, "\(tag): no Disconnect item")
        item.tap()
        XCTAssertTrue(app.buttons["game.Desktop"].waitForExistence(timeout: 10), "\(tag): didn't return to the apps")
        app.terminate()
    }

    /// Daniel's large text: the bar and the key row still fit.
    private func largeText(orientation: UIDeviceOrientation, name: String) {
        let tag = "\(appearance)-\(name)-AX5-desktop"
        let (app, desktop) = connect(size: "UICTContentSizeCategoryAccessibilityXXXL", orientation: orientation)
        let window = app.windows.firstMatch.frame
        for id in ["bar.keyboard", "bar.mode", "bar.rightClick", "bar.shortcuts", "bar.disconnect"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.exists, "\(tag): no \(id)")
            XCTAssertGreaterThanOrEqual(button.frame.minX, window.minX - 1, "\(tag): \(id) off screen")
            XCTAssertLessThanOrEqual(button.frame.maxX, window.maxX + 1, "\(tag): \(id) off screen")
        }
        shot("\(tag)-1-connected")
        app.buttons["bar.keyboard"].tap()
        XCTAssertTrue(app.buttons["key.Esc"].waitForExistence(timeout: 5), "\(tag): no key row")
        sleep(1)
        shot("\(tag)-2-keyboard")
        XCTAssertTrue(desktop.exists)
        app.terminate()
    }
}

/// Several fingers at once, through XCTest's event synthesizer (the private API that
/// WebDriverAgent uses: XCTest has no public multi-finger drag).
enum MultiTouch {
    static func drag(fingers: [CGPoint], by delta: CGVector, duration: TimeInterval, testCase: XCTestCase) -> Bool {
        paths(fingers.map { ($0, delta) }, duration: duration, testCase: testCase)
    }

    /// Each finger from its start point by its own movement (apart: a pinch).
    static func paths(_ fingers: [(CGPoint, CGVector)], duration: TimeInterval, testCase: XCTestCase) -> Bool {
        timed(fingers.map { ($0.0, $0.1, 0, duration, 0) }, testCase: testCase)
    }

    /// Tap, touch again `gap` seconds later, hold still for `hold`, then drag: one finger, two touches.
    static func tapThenDrag(at point: CGPoint, by delta: CGVector, gap: TimeInterval, hold: TimeInterval, testCase: XCTestCase) -> Bool {
        timed([(point, .zero, 0, 0.05, 0), (point, delta, 0.05 + gap, 0.4, hold)], testCase: testCase)
    }

    /// Touches, each from a point by a movement: down at `start`, still for `hold`, then moving
    /// for `duration` (seconds from the start of the event).
    static func timed(_ touches: [(CGPoint, CGVector, TimeInterval, TimeInterval, TimeInterval)], testCase: XCTestCase) -> Bool {
        guard let recordClass = NSClassFromString("XCSynthesizedEventRecord") as? NSObject.Type,
              let pathClass = NSClassFromString("XCPointerEventPath") as? NSObject.Type else { return false }
        // The synthesizer takes points in the upright screen's coordinates, while element
        // frames are in the app's (landscape) ones: rotate them
        let window = XCUIApplication().windows.firstMatch.frame
        let short = min(window.width, window.height), long = max(window.width, window.height)
        let deviceOrientation = XCUIDevice.shared.orientation
        func upright(_ point: CGPoint) -> CGPoint {
            switch deviceOrientation {
            case .landscapeLeft: CGPoint(x: short - point.y, y: point.x)
            case .landscapeRight: CGPoint(x: point.y, y: long - point.x)
            default: point
            }
        }
        func upright(_ vector: CGVector) -> CGVector {
            let a = upright(CGPoint.zero), b = upright(CGPoint(x: vector.dx, y: vector.dy))
            return CGVector(dx: b.x - a.x, dy: b.y - a.y)
        }
        let fingers = touches.map { (upright($0.0), upright($0.1), $0.2, $0.3, $0.4) }
        let total = touches.map { $0.2 + $0.3 + $0.4 }.max() ?? 0
        let orientation = UIInterfaceOrientation.portrait.rawValue

        typealias InitRecord = @convention(c) (AnyObject, Selector, NSString, Int) -> AnyObject
        let initRecord = NSSelectorFromString("initWithName:interfaceOrientation:")
        let recordAlloc = recordClass.perform(NSSelectorFromString("alloc")).takeUnretainedValue()
        guard recordAlloc.responds(to: initRecord) else { return false }
        let record = unsafeBitCast(recordAlloc.method(for: initRecord), to: InitRecord.self)(recordAlloc, initRecord, "Artemis multi-touch", orientation)

        typealias InitPath = @convention(c) (AnyObject, Selector, CGPoint, Double) -> AnyObject
        typealias Move = @convention(c) (AnyObject, Selector, CGPoint, Double) -> Void
        typealias Lift = @convention(c) (AnyObject, Selector, Double) -> Void
        let initPath = NSSelectorFromString("initForTouchAtPoint:offset:")
        let move = NSSelectorFromString("moveToPoint:atOffset:")
        let lift = NSSelectorFromString("liftUpAtOffset:")
        let add = NSSelectorFromString("addPointerEventPath:")
        for (finger, delta, start, duration, hold) in fingers {
            let pathAlloc = pathClass.perform(NSSelectorFromString("alloc")).takeUnretainedValue()
            guard pathAlloc.responds(to: initPath) else { return false }
            let path = unsafeBitCast(pathAlloc.method(for: initPath), to: InitPath.self)(pathAlloc, initPath, finger, start)
            let moveFunction = unsafeBitCast(path.method(for: move), to: Move.self)
            let steps = delta == .zero ? 0 : 12
            for step in stride(from: 1, through: steps, by: 1) {
                let fraction = Double(step) / Double(steps)
                moveFunction(path, move, CGPoint(x: finger.x + delta.dx * fraction, y: finger.y + delta.dy * fraction),
                             start + hold + duration * fraction)
            }
            unsafeBitCast(path.method(for: lift), to: Lift.self)(path, lift, start + hold + max(duration, 0.05) + 0.02)
            _ = record.perform(add, with: path)
        }

        guard let synthesizer = XCUIDevice.shared.perform(NSSelectorFromString("eventSynthesizer"))?.takeUnretainedValue() else { return false }
        typealias Synthesize = @convention(c) (AnyObject, Selector, AnyObject, @escaping @convention(block) (Bool, NSError?) -> Void) -> Void
        let synthesize = NSSelectorFromString("synthesizeEvent:completion:")
        guard synthesizer.responds(to: synthesize) else { return false }
        let done = testCase.expectation(description: "multi-touch")
        var failure: NSError?
        unsafeBitCast(synthesizer.method(for: synthesize), to: Synthesize.self)(synthesizer, synthesize, record) { _, error in
            failure = error
            done.fulfill()
        }
        testCase.wait(for: [done], timeout: total + 10)
        return failure == nil
    }
}
