//
//  DemoData.swift
//  Artemis
//
//  Stand-in PCs for screenshots and UI tests (launch argument -ArtemisDemo YES):
//  a paired PC with apps, one active; an offline PC; a PC that isn't paired.
//  Connecting opens a picture of a desktop that records the input (DemoDesktopViewController);
//  with -ArtemisDemoRealStream YES it opens the real stream screen, which can't reach the PC.
//  Nothing touches the network or the saved PCs in this mode.
//

import UIKit

enum DemoData {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "ArtemisDemo")
    }

    static var usesRealStream: Bool {
        UserDefaults.standard.bool(forKey: "ArtemisDemoRealStream")
    }

    /// Seconds until a woken demo PC answers (-ArtemisDemoWakeDelay; a large number for one that never does).
    static var wakeDelay: Double {
        // double(forKey:) also reads the launch argument's text
        UserDefaults.standard.object(forKey: "ArtemisDemoWakeDelay") == nil ? 3 : UserDefaults.standard.double(forKey: "ArtemisDemoWakeDelay")
    }

    /// A woken demo PC comes up the way discovery sees a real one: its poll (on a background
    /// thread) changes the host's state and posts ArtemisHostUpdated.
    static func simulateWake(_ host: TemporaryHost) {
        let delay = wakeDelay
        guard delay >= 0 else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            host.state = .online
            NotificationCenter.default.post(name: .artemisHostUpdated, object: host)
        }
    }

    static func makeHosts() -> [TemporaryHost] {
        let enchilada = host("ENCHILADA", uuid: "demo-enchilada", state: .online, paired: true, mac: "a8:a1:59:12:34:56")
        let games: [(String, String, Bool)] = [
            ("1", "Desktop", false), ("2", "Visual Studio Code", false), ("3", "Blender", false),
            ("4", "Photoshop", false), ("5", "Terminal", false), ("6", "File Explorer", false),
            ("7", "Steam Big Picture", false), ("8", "Old Virtual Display", true),
        ]
        enchilada.appList = Set(games.map { app($0.0, $0.1, hidden: $0.2, host: enchilada) })
        enchilada.currentGame = "1"

        let livingRoom = host("Living Room PC", uuid: "demo-living-room", state: .offline, paired: true, mac: "a8:a1:59:65:43:21")
        livingRoom.appList = Set([app("1", "Desktop", hidden: false, host: livingRoom)])

        let studio = host("STUDIO", uuid: "demo-studio", state: .online, paired: false, mac: nil)
        return [enchilada, livingRoom, studio]
    }

    private static func host(_ name: String, uuid: String, state: State, paired: Bool, mac: String?) -> TemporaryHost {
        let host = TemporaryHost()
        host.name = name
        host.uuid = uuid
        host.state = state
        host.pairState = paired ? .paired : .unpaired
        host.mac = mac
        host.activeAddress = "127.0.0.1"
        host.address = "127.0.0.1"
        host.httpsPort = 47984
        host.appList = Set()
        return host
    }

    private static func app(_ id: String, _ name: String, hidden: Bool, host: TemporaryHost) -> TemporaryApp {
        let app = TemporaryApp()
        app.id = id
        app.name = name
        app.hidden = hidden
        app.host = host
        return app
    }

    private static let palettes: [(UIColor, UIColor)] = [
        (#colorLiteral(red: 0.98, green: 0.85, blue: 0.1, alpha: 1), #colorLiteral(red: 0.85, green: 0.1, blue: 0.35, alpha: 1)),
        (#colorLiteral(red: 0.75, green: 0.6, blue: 0.3, alpha: 1), #colorLiteral(red: 0.12, green: 0.1, blue: 0.08, alpha: 1)),
        (#colorLiteral(red: 0.95, green: 0.35, blue: 0.2, alpha: 1), #colorLiteral(red: 0.3, green: 0.05, blue: 0.15, alpha: 1)),
        (#colorLiteral(red: 0.2, green: 0.75, blue: 0.95, alpha: 1), #colorLiteral(red: 0.1, green: 0.2, blue: 0.5, alpha: 1)),
        (#colorLiteral(red: 0.9, green: 0.2, blue: 0.3, alpha: 1), #colorLiteral(red: 0.15, green: 0.35, blue: 0.75, alpha: 1)),
        (#colorLiteral(red: 0.35, green: 0.5, blue: 0.95, alpha: 1), #colorLiteral(red: 0.1, green: 0.12, blue: 0.3, alpha: 1)),
        (#colorLiteral(red: 0.2, green: 0.25, blue: 0.35, alpha: 1), #colorLiteral(red: 0.05, green: 0.08, blue: 0.12, alpha: 1)),
        (#colorLiteral(red: 0.55, green: 0.3, blue: 0.75, alpha: 1), #colorLiteral(red: 0.1, green: 0.05, blue: 0.2, alpha: 1)),
    ]

    /// Stand-in artwork: a gradient with the name on it.
    static func boxArt(for game: Game) -> UIImage {
        let (top, bottom) = palettes[(Int(game.appID) ?? 0) % palettes.count]
        let size = CGSize(width: 300, height: 400)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let text = game.name.uppercased() as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 40, weight: .heavy),
                .foregroundColor: UIColor.white,
                .paragraphStyle: style,
            ]
            text.draw(in: CGRect(x: 20, y: size.height - 160, width: size.width - 40, height: 150), withAttributes: attributes)
        }
    }
}
