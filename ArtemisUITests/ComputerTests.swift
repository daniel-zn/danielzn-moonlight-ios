//
//  ComputerTests.swift
//  ArtemisUITests
//
//  The Computers list's actions against the demo PCs (-ArtemisDemo YES): waking an offline PC
//  (by a tap, which then opens it, or from its menu) and the status following the PC, a wake
//  that never comes up, and the PC actions the Mac app has (rename, Get Info, connect
//  automatically).
//

import XCTest

final class ComputerTests: XCTestCase {
    private var appearance: String {
        ProcessInfo.processInfo.environment["ARTEMIS_APPEARANCE"].flatMap { $0.isEmpty ? nil : $0 } ?? "system"
    }

    override func setUp() {
        continueAfterFailure = true
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(_ arguments: [String] = [], size: String = "UICTContentSizeCategoryL") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ArtemisDemo", "YES", "-UIPreferredContentSizeCategoryName", size] + arguments
        app.launch()
        XCTAssertTrue(app.buttons["computer.ENCHILADA"].waitForExistence(timeout: 15), "no demo PCs")
        return app
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

    @discardableResult
    private func waitForLabel(_ element: XCUIElement, contains text: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    private func menuItem(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Long-presses a row and returns its menu's item (pressing again if the menu didn't open).
    private func openMenu(_ row: XCUIElement, item label: String, in app: XCUIApplication) -> XCUIElement {
        let item = menuItem(app, label)
        for _ in 0..<3 {
            row.press(forDuration: 1.3)
            if item.waitForExistence(timeout: 3) { return item }
        }
        print("[tree] \(app.debugDescription)")
        return item
    }

    /// Scrolls the frontmost list until the element can be tapped: up first, then down.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        _ = element.waitForExistence(timeout: 2)
        let list = app.collectionViews.allElementsBoundByIndex.last(where: { $0.isHittable }) ?? app.collectionViews.firstMatch
        for attempt in 0..<12 {
            if element.exists && element.isHittable { return true }
            let up = attempt < 4
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.7 : 0.35))
                .press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.4 : 0.65)))
        }
        return element.exists && element.isHittable
    }

    /// Empties a text field: from its end (a tap mid-text leaves part of it), again while text is
    /// left (keys typed on a busy machine can go missing).
    private func clear(_ field: XCUIElement) {
        for _ in 0..<5 {
            let text = field.value as? String ?? ""
            if text.isEmpty || text == field.placeholderValue { return }
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
            sleep(1)
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count + 2))
        }
    }

    /// Alerts can list a button twice; taps the one on screen, again if the alert was still
    /// moving for the keyboard.
    private func tapHittable(_ query: XCUIElementQuery) {
        for _ in 0..<3 {
            sleep(1)
            guard let match = query.allElementsBoundByIndex.first(where: { $0.isHittable }) else { return }
            match.tap()
        }
    }

    private func disconnect(_ app: XCUIApplication) {
        let button = app.buttons["bar.disconnect"]
        if !button.exists, app.buttons["bar.unfold"].exists { app.buttons["bar.unfold"].tap() }
        XCTAssertTrue(button.waitForExistence(timeout: 5), "no Disconnect")
        button.tap()
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Disconnect", "bar.disconnect")).firstMatch.tap()
    }

    /// Tapping an offline PC wakes it, shows "Waking up…", and opens its apps once it's up.
    func testTapWakesThenOpens() {
        let app = launch(["-ArtemisDemoWakeDelay", "3"])
        let livingRoom = app.buttons["computer.Living Room PC"]
        XCTAssertTrue(livingRoom.waitForExistence(timeout: 5))
        XCTAssertTrue(livingRoom.label.contains("Tap to wake"), "status: \(livingRoom.label)")
        livingRoom.tap()
        XCTAssertTrue(waitForLabel(livingRoom, contains: "Waking up", timeout: 3), "no Waking up (\(livingRoom.label))")
        shot("\(appearance)-portrait-L-wake-1-waking")
        XCTAssertTrue(app.buttons["game.Desktop"].waitForExistence(timeout: 15), "the PC woke but its apps didn't open")
        XCTAssertEqual(app.navigationBars.firstMatch.identifier, "Living Room PC")
        shot("\(appearance)-portrait-L-wake-2-opened")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(waitForLabel(livingRoom, contains: "Online", timeout: 5), "status after waking: \(livingRoom.label)")
        XCTAssertFalse(livingRoom.label.contains("Waking"), "still waking: \(livingRoom.label)")
        app.terminate()
    }

    /// Wake PC from the long-press menu: "Waking up…" turns into Online when the PC is up,
    /// and nothing opens by itself.
    func testMenuWakeFollowsThePC() {
        let app = launch(["-ArtemisDemoWakeDelay", "3"])
        let livingRoom = app.buttons["computer.Living Room PC"]
        XCTAssertTrue(livingRoom.waitForExistence(timeout: 5))
        let wake = openMenu(livingRoom, item: "Wake PC", in: app)
        XCTAssertTrue(wake.exists, "no Wake PC in the menu")
        shot("\(appearance)-portrait-L-wake-3-menu")
        wake.tap()
        XCTAssertTrue(waitForLabel(livingRoom, contains: "Waking up", timeout: 3), "no Waking up (\(livingRoom.label))")
        XCTAssertTrue(waitForLabel(livingRoom, contains: "Online", timeout: 15), "stuck: \(livingRoom.label)")
        XCTAssertFalse(livingRoom.label.contains("Waking"), "still waking: \(livingRoom.label)")
        XCTAssertFalse(app.buttons["game.Desktop"].exists, "the menu's wake opened the PC")
        shot("\(appearance)-portrait-L-wake-4-online")
        app.terminate()
    }

    /// A PC that never comes up: back to Offline after the timeout, with a message.
    func testWakeTimesOut() {
        let app = launch(["-ArtemisDemoWakeDelay", "9999", "-ArtemisWakeTimeout", "5"])
        let livingRoom = app.buttons["computer.Living Room PC"]
        XCTAssertTrue(livingRoom.waitForExistence(timeout: 5))
        livingRoom.tap()
        XCTAssertTrue(waitForLabel(livingRoom, contains: "Waking up", timeout: 3), "no Waking up (\(livingRoom.label))")
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 15), "no message after the wake timed out")
        XCTAssertTrue(alert.label.contains("Didn't Wake Up"), "alert: \(alert.label)")
        shot("\(appearance)-portrait-L-wake-5-timeout")
        alert.buttons["OK"].tap()
        XCTAssertTrue(waitForLabel(livingRoom, contains: "Offline", timeout: 3), "status: \(livingRoom.label)")
        XCTAssertFalse(livingRoom.label.contains("Waking"), "still waking: \(livingRoom.label)")
        app.terminate()
    }

    // MARK: The Mac app's PC and app actions

    /// Rename… and Get Info from a PC's menu; an empty name goes back to the PC's own.
    func testRenameAndGetInfo() {
        for (orientation, size, name) in [(UIDeviceOrientation.portrait, "UICTContentSizeCategoryL", "portrait-L"),
                                          (.landscapeLeft, "UICTContentSizeCategoryL", "landscape-L"),
                                          (.portrait, "UICTContentSizeCategoryAccessibilityXXXL", "portrait-AX5")] {
            let tag = "\(appearance)-\(name)"
            let app = launch(size: size)
            XCUIDevice.shared.orientation = orientation
            let enchilada = app.buttons["computer.ENCHILADA"]
            let rename = openMenu(enchilada, item: "Rename…", in: app)
            XCTAssertTrue(rename.exists, "\(tag): no Rename…")
            XCTAssertTrue(menuItem(app, "Get Info").exists, "\(tag): no Get Info")
            XCTAssertTrue(menuItem(app, "Test Network…").exists, "\(tag): no Test Network…")
            shot("\(tag)-parity-1-pc-menu")
            rename.tap()
            let field = app.alerts.textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5), "\(tag): no name field")
            clear(field)
            field.typeText("Office PC")
            shot("\(tag)-parity-2-rename")
            tapHittable(app.alerts.buttons.matching(identifier: "rename.confirm"))
            let office = app.buttons["computer.Office PC"]
            XCTAssertTrue(office.waitForExistence(timeout: 5), "\(tag): the PC wasn't renamed")

            let info = openMenu(office, item: "Get Info", in: app)
            XCTAssertTrue(info.exists, "\(tag): no Get Info")
            info.tap()
            XCTAssertTrue(app.buttons["info.done"].waitForExistence(timeout: 5), "\(tag): Get Info didn't open")
            sleep(1)
            shot("\(tag)-parity-3-get-info")
            for text in ["PC's own name", "ENCHILADA", "a8:a1:59:12:34:56", "Paired", "47984", "127.0.0.1"] {
                let value = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
                XCTAssertTrue(reveal(value, in: app), "\(tag): Get Info has no \(text)")
            }
            app.buttons["info.done"].tap()

            // Back to the PC's own name
            openMenu(office, item: "Rename…", in: app).tap()
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            clear(field)
            XCTAssertEqual(field.value as? String ?? "", field.placeholderValue ?? "", "\(tag): the name field isn't empty")
            tapHittable(app.alerts.buttons.matching(identifier: "rename.confirm"))
            XCTAssertTrue(enchilada.waitForExistence(timeout: 5), "\(tag): the empty name didn't restore ENCHILADA")
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
    }

    /// Connect Automatically When Opening PC: opening the PC connects to that app; View All
    /// Apps, Including Hidden doesn't.
    func testConnectAutomatically() {
        let tag = "\(appearance)-portrait-L"
        let app = launch()
        let enchilada = app.buttons["computer.ENCHILADA"]
        enchilada.tap()
        let desktopApp = app.buttons["game.Desktop"]
        XCTAssertTrue(desktopApp.waitForExistence(timeout: 10))
        let toggle = openMenu(desktopApp, item: "Connect Automatically When Opening PC", in: app)
        XCTAssertTrue(toggle.exists, "no Connect Automatically")
        XCTAssertTrue(menuItem(app, "Stop").exists, "no Stop in the active app's menu")
        shot("\(tag)-parity-4-app-menu")
        toggle.tap()
        XCTAssertTrue(app.staticTexts["game.directLaunch"].waitForExistence(timeout: 5), "no Connects automatically note")
        sleep(1)
        shot("\(tag)-parity-5-connects-automatically")
        app.navigationBars.buttons.firstMatch.tap()

        enchilada.tap()
        XCTAssertTrue(app.otherElements["desktop"].waitForExistence(timeout: 10), "opening the PC didn't connect")
        disconnect(app)
        XCTAssertTrue(desktopApp.waitForExistence(timeout: 10), "didn't return to the apps")
        app.navigationBars.buttons.firstMatch.tap()

        openMenu(enchilada, item: "View All Apps, Including Hidden", in: app).tap()
        XCTAssertTrue(app.buttons["game.Old Virtual Display"].waitForExistence(timeout: 10), "hidden apps don't show")
        sleep(2)
        XCTAssertFalse(app.otherElements["desktop"].exists, "View All Apps connected by itself")
        app.terminate()
    }

    /// Settings › Host PC › Stop the app on the PC after a session.
    func testEndAppAfterSession() {
        let app = launch(["-ArtemisQuitAppAfterSession", "YES"])
        app.buttons["computer.ENCHILADA"].tap()
        let desktopApp = app.buttons["game.Desktop"]
        XCTAssertTrue(desktopApp.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["game.running"].exists, "Desktop isn't active to begin with")
        desktopApp.tap()
        XCTAssertTrue(app.otherElements["desktop"].waitForExistence(timeout: 10))
        disconnect(app)
        XCTAssertTrue(desktopApp.waitForExistence(timeout: 10), "didn't return to the apps")
        let ended = NSPredicate(format: "exists == false")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ended, object: app.staticTexts["game.running"])], timeout: 10),
                       .completed, "the app is still active after disconnecting")
        app.terminate()
    }

    /// The new and changed Settings pages.
    func testSettingsPages() {
        for (orientation, size, name) in [(UIDeviceOrientation.portrait, "UICTContentSizeCategoryL", "portrait-L"),
                                          (.landscapeLeft, "UICTContentSizeCategoryL", "landscape-L"),
                                          (.portrait, "UICTContentSizeCategoryAccessibilityXXXL", "portrait-AX5")] {
            let tag = "\(appearance)-\(name)"
            let app = launch(size: size)
            XCUIDevice.shared.orientation = orientation
            app.buttons["computers.settings"].tap()
            XCTAssertTrue(app.buttons["settings.video"].waitForExistence(timeout: 5))
            for (section, element) in [("audio", "settings.microphone"), ("keyboard", ""),
                                       ("controllers", "settings.gamepadMouse"), ("host", "settings.quitAfterSession")] {
                let row = app.buttons["settings.\(section)"]
                XCTAssertTrue(reveal(row, in: app), "\(tag): no \(section) section")
                row.tap()
                if !element.isEmpty {
                    XCTAssertTrue(reveal(app.switches[element], in: app), "\(tag): no \(element)")
                }
                sleep(1)
                shot("\(tag)-parity-6-settings-\(section)")
                app.navigationBars.buttons.firstMatch.tap()
                sleep(1)
            }
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
    }

    // MARK: Crashes

    /// Daniel's crash (build 1267): long-pressing Apollo's own apps (Steam Big Picture, Virtual
    /// Display), whose artwork arrives while the menu is open. The menu's artwork preview is
    /// drawn outside the list and lost the store when it re-rendered.
    func testLongPressAppsWhileArtworkArrives() {
        let app = launch()
        app.buttons["computer.ENCHILADA"].tap()
        XCTAssertTrue(app.buttons["game.Desktop"].waitForExistence(timeout: 10))
        for name in ["Steam Big Picture", "Virtual Display", "Desktop"] {
            let row = app.buttons["game.\(name)"]
            XCTAssertTrue(reveal(row, in: app), "no \(name)")
            let connect = openMenu(row, item: name == "Desktop" ? "Resume" : "Connect", in: app)
            XCTAssertTrue(connect.exists, "\(name): no menu")
            // Artwork keeps arriving for a few seconds with the menu (and its preview) open
            sleep(4)
            XCTAssertEqual(app.state, .runningForeground, "\(name): the app crashed with the menu open")
            shot("\(appearance)-portrait-L-crash-menu-\(name)")
            // Close the menu
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
            sleep(1)
            XCTAssertEqual(app.state, .runningForeground, "\(name): the app crashed closing the menu")
        }
        app.terminate()
    }

    /// Sessions default to the iPhone's own resolution: settings still at upstream's 1280 × 720
    /// move to Native once.
    func testNativeResolutionDefault() {
        let app = launch(["-ArtemisTestOldDefaultResolution", "YES"])
        app.buttons["computers.settings"].tap()
        let summary = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Sessions use Native at")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "not Native: \(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Sessions use'")).firstMatch.label)")
        app.buttons["settings.video"].tap()
        let picker = app.buttons["settings.resolution"].exists ? app.buttons["settings.resolution"] : app.otherElements["settings.resolution"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let text = "\(picker.label) \(picker.value as? String ?? "")"
        XCTAssertTrue(text.contains("Native") && !text.contains("Excluding"), "resolution picker: \(text)")
        sleep(1)
        shot("\(appearance)-portrait-L-native-resolution")
        app.terminate()
    }
}
