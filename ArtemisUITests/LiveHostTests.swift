//
//  LiveHostTests.swift
//  ArtemisUITests
//
//  Against a real host on the network (ARTEMIS_LIVE_HOST=<name>[@<address>]; skipped
//  without it): it shows up in Computers, by discovery or added by address, and opening it
//  shows its games when paired, or the pairing PIN, which this test cancels (it never pairs).
//

import XCTest

final class LiveHostTests: XCTestCase {
    func testRealHostOpens() throws {
        guard let spec = ProcessInfo.processInfo.environment["ARTEMIS_LIVE_HOST"], !spec.isEmpty else {
            throw XCTSkip("set ARTEMIS_LIVE_HOST=<name>[@<address>]")
        }
        let parts = spec.split(separator: "@").map(String.init)
        let name = parts[0]
        let dir = ProcessInfo.processInfo.environment["ARTEMIS_SHOT_DIR"] ?? ""
        func shot(_ label: String) {
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = label
            attachment.lifetime = .keepAlways
            add(attachment)
            if !dir.isEmpty {
                try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("live-\(label).png"))
            }
        }

        let app = XCUIApplication()
        app.launchArguments = ["-ArtemisDemo", "NO"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait

        // The local network permission prompt, the first time
        addUIInterruptionMonitor(withDescription: "Local network") { alert in
            for label in ["Allow", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.buttons["Allow"].waitForExistence(timeout: 5) {
            springboard.alerts.buttons["Allow"].tap()
        }

        let row = app.buttons["computer.\(name)"]
        if !row.waitForExistence(timeout: 30), parts.count > 1 {
            app.buttons["computers.add"].tap()
            let field = app.textFields["add.address"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.typeText(parts[1])
            app.buttons["add.confirm"].tap()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 60), "\(name) didn't show up")
        // Its status once known
        let known = NSPredicate(format: "NOT (label CONTAINS 'Connecting')")
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: known, object: row)], timeout: 30)
        print("[live] row: \(row.label)")
        shot("1-computers")

        row.tap()
        let pin = app.staticTexts["pairing.pin"]
        let games = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'game.'")).firstMatch
        let shown = XCTWaiter.wait(for: [
            XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: pin),
        ], timeout: 30) == .completed || games.waitForExistence(timeout: 5)
        XCTAssertTrue(shown, "opening \(name) showed neither its games nor a PIN")
        if pin.exists {
            print("[live] pairing PIN shown: \(pin.label)")
            shot("2-pairing")
            app.buttons["pairing.cancel"].tap()
        } else {
            print("[live] games shown")
            shot("2-games")
        }
    }
}
