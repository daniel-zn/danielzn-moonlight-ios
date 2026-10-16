//
//  DemoDesktop.swift
//  Artemis
//
//  The demo mode's connected screen (-ArtemisDemo YES): a drawn 1920×1080 desktop instead
//  of a stream, with the real controls, recording the input they produce for the UI tests
//  and screenshots.
//

import UIKit

final class DemoDesktopViewController: UIViewController {
    private let appName: String
    private let onExit: () -> Void
    private let input = RecordingDesktopInput()
    private var desktop: DesktopViewController!

    init(appName: String, onExit: @escaping () -> Void) {
        self.appName = appName
        self.onExit = onExit
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let picture = DemoDesktopView(image: Self.desktopImage)
        desktop = DesktopViewController(contentView: picture, streamSize: CGSize(width: 1920, height: 1080),
                                        input: input, title: appName, localCursor: true)
        picture.touchHandler = desktop.touchHandler
        desktop.recordedEvents = { [weak self] in self?.input.events ?? [] }
        input.onChange = { [weak self] in self?.desktop.updateAccessibilityValue() }
        desktop.onDisconnect = { [weak self] in
            guard let self else { return }
            let onExit = self.onExit
            self.presentingViewController?.dismiss(animated: true) { onExit() }
        }
        addChild(desktop)
        desktop.view.frame = view.bounds
        desktop.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(desktop.view)
        desktop.didMove(toParent: self)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
    override var prefersStatusBarHidden: Bool { true }
    override var childForHomeIndicatorAutoHidden: UIViewController? { desktop }

    /// A Windows-like desktop: wallpaper, icons, an editor window and the taskbar.
    static let desktopImage: UIImage = {
        let size = CGSize(width: 1920, height: 1080)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let colors = [UIColor(red: 0.05, green: 0.18, blue: 0.42, alpha: 1).cgColor,
                          UIColor(red: 0.28, green: 0.55, blue: 0.85, alpha: 1).cgColor,
                          UIColor(red: 0.85, green: 0.62, blue: 0.75, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.6, 1])!
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size.width, y: size.height), options: [])

            func text(_ string: String, _ point: CGPoint, size: CGFloat, color: UIColor = .white, weight: UIFont.Weight = .regular) {
                (string as NSString).draw(at: point, withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
            }

            // Desktop icons
            let icons = ["Recycle Bin", "This PC", "Projects", "Blender", "Steam"]
            for (index, name) in icons.enumerated() {
                let origin = CGPoint(x: 40, y: 40 + CGFloat(index) * 130)
                UIColor.white.withAlphaComponent(0.85).setFill()
                UIBezierPath(roundedRect: CGRect(x: origin.x + 18, y: origin.y, width: 64, height: 64), cornerRadius: 12).fill()
                text(name, CGPoint(x: origin.x, y: origin.y + 72), size: 18)
            }

            // A text editor window
            let window = CGRect(x: 420, y: 140, width: 1080, height: 660)
            cg.setShadow(offset: CGSize(width: 0, height: 12), blur: 40, color: UIColor.black.withAlphaComponent(0.45).cgColor)
            UIColor(white: 0.98, alpha: 1).setFill()
            UIBezierPath(roundedRect: window, cornerRadius: 10).fill()
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor(white: 0.93, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: window.minX, y: window.minY, width: window.width, height: 52), byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 10, height: 10)).fill()
            text("notes.txt – Notepad", CGPoint(x: window.minX + 20, y: window.minY + 14), size: 20, color: .darkGray)
            for (index, glyph) in ["–", "□", "✕"].enumerated() {
                text(glyph, CGPoint(x: window.maxX - 150 + CGFloat(index) * 50, y: window.minY + 12), size: 22, color: .darkGray)
            }
            let lines = [
                "Artemis demo desktop",
                "",
                "Trackpad: drag one finger to move the pointer, tap to click.",
                "Two fingers: tap to right-click, drag to scroll, pinch to zoom.",
                "Three fingers: tap for the keyboard.",
                "",
                "The quick brown fox jumps over the lazy dog. 0123456789",
            ]
            for (index, line) in lines.enumerated() {
                text(line, CGPoint(x: window.minX + 32, y: window.minY + 84 + CGFloat(index) * 40), size: 26,
                     color: UIColor(white: 0.15, alpha: 1), weight: index == 0 ? .semibold : .regular)
            }

            // Taskbar
            UIColor(white: 0.1, alpha: 0.88).setFill()
            UIBezierPath(rect: CGRect(x: 0, y: size.height - 60, width: size.width, height: 60)).fill()
            for index in 0..<6 {
                let colorsBar: [UIColor] = [.systemBlue, .systemYellow, .systemGreen, .systemOrange, .systemPurple, .systemTeal]
                colorsBar[index].setFill()
                UIBezierPath(roundedRect: CGRect(x: 760 + CGFloat(index) * 66, y: size.height - 48, width: 36, height: 36), cornerRadius: 8).fill()
            }
            text("12:00", CGPoint(x: size.width - 110, y: size.height - 44), size: 22)
        }
    }()
}

/// The demo's desktop picture; hands its touches to the desktop controls, as StreamView does.
final class DemoDesktopView: UIImageView {
    weak var touchHandler: DesktopTouchHandler?

    override init(image: UIImage?) {
        super.init(image: image)
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = true
        contentMode = .scaleAspectFit
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var canBecomeFirstResponder: Bool { true }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { touchHandler?.touchesBegan(touches, with: event) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { touchHandler?.touchesMoved(touches, with: event) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { touchHandler?.touchesEnded(touches, with: event) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touchHandler?.touchesCancelled(touches, with: event) }
}
