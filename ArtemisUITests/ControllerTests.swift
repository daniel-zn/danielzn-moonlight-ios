//
//  ControllerTests.swift
//  ArtemisUITests
//
//  A game controller as the mouse (GamepadMouse) on the demo desktop: the demo plays a
//  scripted controller (-ArtemisDemoGamepad) into the same mapping ControllerSupport feeds,
//  and the desktop records what reaches the PC: mouse events, or "pad <buttons>" for states
//  sent as a gamepad.
//

import XCTest

final class ControllerTests: XCTestCase {
    private var appearance: String {
        ProcessInfo.processInfo.environment["ARTEMIS_APPEARANCE"].flatMap { $0.isEmpty ? nil : $0 } ?? "system"
    }

    override func setUp() {
        continueAfterFailure = true
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

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

    /// Opens the demo desktop with a controller script; returns its recorded events once it ran.
    private func run(_ script: String, orientation: UIDeviceOrientation, extra: [String] = []) -> (XCUIApplication, String, [String]) {
        let app = XCUIApplication()
        app.launchArguments = ["-ArtemisDemo", "YES", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
                               "-ArtemisShowControlBar", "YES", "-ArtemisBarCenter", "{0.5, 0.92}",
                               "-ArtemisDemoGamepad", script] + extra
        app.launch()
        XCUIDevice.shared.orientation = orientation
        XCTAssertTrue(app.buttons["computer.ENCHILADA"].waitForExistence(timeout: 15))
        app.buttons["computer.ENCHILADA"].tap()
        XCTAssertTrue(app.buttons["game.Desktop"].waitForExistence(timeout: 10))
        app.buttons["game.Desktop"].tap()
        let desktop = app.otherElements["desktop"]
        XCTAssertTrue(desktop.waitForExistence(timeout: 10), "the desktop didn't open")
        // The script runs a second after the desktop opens; the notice shows for 2.5 s after it
        sleep(2)
        let lines = (desktop.value as? String ?? "").components(separatedBy: "\n")
        return (app, lines.first ?? "", Array(lines.dropFirst(2)))
    }

    /// Off: gamepad. Hold Start: mouse (stick moves, A/B click, right stick and D-pad scroll),
    /// with nothing sent as a gamepad. Hold Start again: gamepad again.
    func testControllerMouseMapping() {
        let script = "press a;hold start 0.8;left 1 0 0.25;press a;press b;right 0 1 0.25;press up;hold start 0.8;press a"
        let (app, status, events) = run(script, orientation: .portrait)
        let moves = events.filter { $0.hasPrefix("move ") }
        let stickScrolls = events.filter { $0.hasPrefix("scroll ") && $0 != "scroll 120 0" }
        let others = events.filter { !$0.hasPrefix("move ") && !stickScrolls.contains($0) }
        XCTAssertEqual(others, ["pad 0x1000", "pad 0x0000", // A as a gamepad button
                                "pad 0x0010", "pad 0x0000", // Start held, then up: mouse on
                                "down left", "up left", "down right", "up right", "scroll 120 0",
                                "pad 0x0000", // Start held again: mouse off, the PC sees the controller at rest
                                "pad 0x1000", "pad 0x0000"], "events: \(events)")
        // The left stick, full right for 0.25 s: the pointer goes right from the middle
        XCTAssertGreaterThanOrEqual(moves.count, 10, "moves: \(moves)")
        let last = moves.last?.split(separator: " ").compactMap { Int($0) } ?? []
        XCTAssertEqual(last.count, 2)
        if last.count == 2 {
            XCTAssertTrue((1290...1340).contains(last[0]), "pointer x \(last[0])")
            XCTAssertEqual(last[1], 540, "pointer y")
        }
        // The right stick, up: scrolls up in quarter notches
        XCTAssertGreaterThanOrEqual(stickScrolls.count, 8, "scrolls: \(stickScrolls)")
        XCTAssertTrue(stickScrolls.allSatisfy { $0.hasPrefix("scroll ") && $0.hasSuffix(" 0") && !$0.contains("-") }, "scrolls: \(stickScrolls)")
        XCTAssertTrue(status.contains("gamepad mouse off"), "status: \(status)")
        shot("\(appearance)-portrait-L-controller-1-off")
        app.terminate()
    }

    /// The mouse on, upright and in landscape (the notice and the moved pointer).
    func testControllerMouseOn() {
        for (orientation, name) in [(UIDeviceOrientation.portrait, "portrait"), (.landscapeLeft, "landscape")] {
            let (app, status, events) = run("hold start 0.8;left -0.7 0.7 0.4", orientation: orientation)
            XCTAssertTrue(status.contains("gamepad mouse on"), "\(name) status: \(status)")
            XCTAssertTrue(events.contains { $0.hasPrefix("move ") }, "\(name): no pointer movement")
            XCTAssertTrue(app.staticTexts["desktop.toast"].exists, "\(name): no notice")
            shot("\(appearance)-\(name)-L-controller-2-on")
            app.terminate()
        }
    }

    /// Start held together with another button (Start+LB, as upstream's Select emulation uses)
    /// is a combo, not a long press: the mouse stays off and everything goes to the PC.
    func testControllerComboDoesNotToggle() {
        let (app, status, events) = run("down start;wait 0.4;press lb;wait 0.6;up start;press a", orientation: .portrait)
        XCTAssertEqual(events, ["pad 0x0010", "pad 0x0110", "pad 0x0010", "pad 0x0000", "pad 0x1000", "pad 0x0000"])
        XCTAssertTrue(status.contains("gamepad mouse off"), "status: \(status)")
        app.terminate()
    }

    /// With the setting off, holding Start does nothing: every state goes to the PC.
    func testControllerMouseSettingOff() {
        let (app, status, events) = run("hold start 0.8;press a", orientation: .portrait, extra: ["-ArtemisGamepadMouse", "NO"])
        XCTAssertEqual(events, ["pad 0x0010", "pad 0x0000", "pad 0x1000", "pad 0x0000"])
        XCTAssertTrue(status.contains("gamepad mouse off"), "status: \(status)")
        app.terminate()
    }
}
