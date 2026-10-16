//
//  HomeScreenIconTests.swift
//  ArtemisUITests
//
//  The app icon on the home screen: a screenshot of the page it's on, and a close-up.
//

import XCTest

final class HomeScreenIconTests: XCTestCase {
    func testHomeScreenIcon() {
        let appearance = ProcessInfo.processInfo.environment["ARTEMIS_APPEARANCE"].flatMap { $0.isEmpty ? nil : $0 } ?? "system"
        let dir = ProcessInfo.processInfo.environment["ARTEMIS_SHOT_DIR"] ?? ""
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = springboard.icons["Artemis"]
        XCTAssertTrue(icon.waitForExistence(timeout: 10), "no Artemis icon on the home screen")
        for _ in 0..<4 where !icon.isHittable {
            springboard.swipeLeft()
            sleep(1)
        }
        XCTAssertTrue(icon.isHittable, "the Artemis icon isn't on screen")
        sleep(1)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "home-\(appearance)"
        attachment.lifetime = .keepAlways
        add(attachment)
        guard !dir.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(appearance)-home.png"))
        // A close-up of the icon and its label, in pixels
        let scale = screenshot.image.scale
        let frame = icon.frame.insetBy(dx: -24, dy: -16)
        if let cg = screenshot.image.cgImage?.cropping(to: CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)),
           let png = UIImage(cgImage: cg).pngData() {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(appearance)-home-icon.png"))
        }
    }
}
