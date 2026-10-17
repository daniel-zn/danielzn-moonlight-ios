//
//  DesktopViewController.swift
//  Artemis
//
//  The connected screen's controls around the desktop (docs/TOUCH.md): the desktop view
//  (upstream's StreamView, or the demo picture) in a zoomable canvas, the touch gestures,
//  the control bar, the keyboard with its key row, and the trackpad area when upright.
//  StreamFrameViewController keeps the connection; this sends the input.
//

import SwiftUI
import UIKit

@objc(DesktopViewController)
final class DesktopViewController: UIViewController {
    /// Disconnect from the control bar.
    @objc var onDisconnect: (() -> Void)?
    /// Receives the desktop view's finger touches (StreamView hands them over).
    @objc private(set) lazy var touchHandler = DesktopTouchHandler(controller: self)

    let session: DesktopSession
    private let input: DesktopInput
    private let contentView: UIView
    private let streamSize: CGSize
    private var pointerSettings = PointerSettings.load()

    private let canvas = DesktopCanvasView()
    private let trackpadArea = TrackpadAreaView()
    private let keyCapture = KeyCaptureView()
    private let keyboardSpacer = UIView()
    /// Upright: resets the zoom, on the desktop's corner (landscape has it in the bar).
    private let fitButton = UIButton(configuration: .glass())
    private lazy var barHost = UIHostingController(rootView: ControlBar(session: session))
    private let interpreter = TouchInterpreter()
    /// The demo draws its own pointer; a real stream shows the PC's.
    private let localCursor: UIImageView?

    // Zoom: the content's scale and its centre's offset from the canvas's centre
    private var scale: CGFloat = 1
    private var offset = CGPoint.zero

    /// Where the pointer is on the desktop (0–1).
    private var pointer = CGPoint(x: 0.5, y: 0.5)
    private var scrollRemainder = CGVector.zero
    private var momentumVelocity = CGVector.zero
    private var momentumLink: CADisplayLink?
    private var lastMomentumTime: CFTimeInterval = 0
    private var buttonModifiers: [MouseButton: [Modifier]] = [:]

    /// The floating bar's centre, as a fraction of the screen (landscape).
    private var barCenter: CGPoint
    private var barDragStart: CGPoint?

    /// Called when the demo's recorded input or the view's state changes (UI tests).
    var recordedEvents: (() -> [String])?

    @objc init(contentView: UIView, streamSize: CGSize, input: DesktopInput, title: String, localCursor: Bool) {
        self.contentView = contentView
        self.streamSize = streamSize.width > 0 && streamSize.height > 0 ? streamSize : CGSize(width: 1920, height: 1080)
        self.input = input
        let absolute = (DataManager().getSettings()?.absoluteTouchMode) ?? false
        let pointer = PointerSettings.load()
        session = DesktopSession(title: title, mode: absolute ? .direct : .trackpad, barExpanded: pointer.showControlBar)
        let saved = UserDefaults.standard.string(forKey: "ArtemisBarCenter").map(NSCoder.cgPoint(for:))
        barCenter = saved ?? CGPoint(x: 0.5, y: 0.92)
        self.localCursor = localCursor ? UIImageView(image: DesktopViewController.cursorImage) : nil
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: View

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        interpreter.delegate = self

        canvas.backgroundColor = .black
        canvas.clipsToBounds = true
        canvas.isAccessibilityElement = true
        canvas.accessibilityLabel = "Remote desktop"
        canvas.accessibilityTraits = .allowsDirectInteraction
        canvas.accessibilityIdentifier = "desktop"
        canvas.touchHandler = touchHandler
        view.addSubview(canvas)
        canvas.addSubview(contentView)
        if let localCursor {
            localCursor.isUserInteractionEnabled = false
            contentView.addSubview(localCursor)
        }

        var fit = UIButton.Configuration.glass()
        fit.image = UIImage(systemName: "arrow.down.right.and.arrow.up.left",
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        fit.baseForegroundColor = .label
        fitButton.configuration = fit
        fitButton.accessibilityLabel = "Reset Zoom"
        fitButton.accessibilityIdentifier = "bar.resetZoom"
        fitButton.addAction(UIAction { [weak self] _ in self?.resetZoomAnimated() }, for: .primaryActionTriggered)
        fitButton.isHidden = true
        view.addSubview(fitButton)

        trackpadArea.touchHandler = touchHandler
        trackpadArea.onButton = { [weak self] button, down in
            self?.setButton(button, down: down)
            if down { self?.haptic(.light) }
        }
        view.addSubview(trackpadArea)

        keyCapture.onText = { [weak self] in self?.typed($0) }
        keyCapture.onDelete = { [weak self] in self?.sendKey(KeyCode.backspace) }
        keyCapture.onHardwareKey = { [weak self] press, down in
            guard self?.input is MoonlightDesktopInput else { return false }
            return KeyboardSupport.sendKeyEvent(for: press, down: down)
        }
        keyCapture.accessory = makeKeyRow()
        view.addSubview(keyCapture)

        // Keeps the layout following the keyboard
        view.keyboardLayoutGuide.usesBottomSafeArea = false
        keyboardSpacer.isUserInteractionEnabled = false
        keyboardSpacer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardSpacer)
        NSLayoutConstraint.activate([
            keyboardSpacer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardSpacer.widthAnchor.constraint(equalToConstant: 1),
            keyboardSpacer.topAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            keyboardSpacer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        barHost.view.backgroundColor = .clear
        barHost.sizingOptions = [.intrinsicContentSize]
        addChild(barHost)
        view.addSubview(barHost.view)
        barHost.didMove(toParent: self)

        session.actions = makeActions()

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(keyboardChanged), name: UIResponder.keyboardDidHideNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardChanged), name: UIResponder.keyboardDidShowNotification, object: nil)
        updateAccessibilityValue()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Hardware keyboards type into the desktop view (upstream's StreamView handles them)
        if !keyCapture.isFirstResponder {
            contentView.becomeFirstResponder()
        }
    }

    deinit {
        momentumLink?.invalidate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        let insets = view.safeAreaInsets
        let keyboardTop = min(bounds.maxY, keyboardSpacer.frame.minY > 0 ? keyboardSpacer.frame.minY : bounds.maxY)
        let portrait = bounds.height > bounds.width
        if session.isPortrait != portrait {
            session.isPortrait = portrait
        }
        let barSize = barHost.sizeThatFits(in: CGSize(width: portrait ? bounds.width : bounds.width - insets.left - insets.right,
                                                      height: bounds.height))
        if portrait {
            // The desktop across the top, the bar under it, then the trackpad
            let aspect = streamSize.width / streamSize.height
            let available = max(120, keyboardTop - insets.top - barSize.height - 16)
            let height = min(bounds.width / aspect, available)
            canvas.frame = CGRect(x: 0, y: insets.top, width: bounds.width, height: height)
            barHost.view.frame = CGRect(x: 0, y: canvas.frame.maxY + 8, width: bounds.width, height: barSize.height)
            let areaTop = barHost.view.frame.maxY + 10
            let areaBottom = keyboardTop < bounds.maxY ? keyboardTop - 8 : bounds.maxY - max(insets.bottom, 12)
            trackpadArea.isHidden = areaBottom - areaTop < 60
            trackpadArea.frame = CGRect(x: 12, y: areaTop, width: bounds.width - 24, height: max(0, areaBottom - areaTop))
        } else {
            // Full screen; with the keyboard up, the space above it
            canvas.frame = CGRect(x: 0, y: 0, width: bounds.width, height: keyboardTop)
            trackpadArea.isHidden = true
            let minX = insets.left + barSize.width / 2 + 8
            let maxX = bounds.width - insets.right - barSize.width / 2 - 8
            let minY = max(insets.top, 8) + barSize.height / 2
            let maxY = min(bounds.height - max(insets.bottom, 8), keyboardTop - 8) - barSize.height / 2
            let center = CGPoint(x: min(max(barCenter.x * bounds.width, minX), max(minX, maxX)),
                                 y: min(max(barCenter.y * bounds.height, minY), max(minY, maxY)))
            barHost.view.bounds = CGRect(origin: .zero, size: barSize)
            barHost.view.center = center
        }
        layoutContent()
        fitButton.frame = CGRect(x: canvas.frame.maxX - 52, y: canvas.frame.minY + 8, width: 44, height: 44)
        view.bringSubviewToFront(fitButton)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in self.view.setNeedsLayout(); self.view.layoutIfNeeded() })
    }

    /// A mouse moved the pointer (StreamView): the trackpad continues from there.
    @objc func pointerMovedExternally(to normalized: CGPoint) {
        pointer = CGPoint(x: min(max(normalized.x, 0), 1), y: min(max(normalized.y, 0), 1))
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopMomentum()
    }

    /// The desktop picture's frame in this view, for the connection status over it.
    @objc var canvasFrame: CGRect {
        canvas.frame
    }

    // MARK: Zoom

    /// The desktop's rectangle in the content view (letterboxed to the stream's shape).
    private func videoRect(in size: CGSize) -> CGRect {
        let aspect = streamSize.width / streamSize.height
        var video = CGSize(width: size.width, height: size.width / aspect)
        if video.height > size.height {
            video = CGSize(width: size.height * aspect, height: size.height)
        }
        return CGRect(x: (size.width - video.width) / 2, y: (size.height - video.height) / 2, width: video.width, height: video.height)
    }

    private func layoutContent() {
        let size = canvas.bounds.size
        contentView.transform = .identity
        contentView.bounds = CGRect(origin: .zero, size: size)
        clampOffset()
        contentView.center = CGPoint(x: size.width / 2 + offset.x, y: size.height / 2 + offset.y)
        contentView.transform = CGAffineTransform(scaleX: scale, y: scale)
        if let localCursor {
            let video = videoRect(in: size)
            let width = max(14, video.width * 0.018)
            localCursor.frame = CGRect(x: video.minX + pointer.x * video.width, y: video.minY + pointer.y * video.height,
                                       width: width, height: width * 1.5)
        }
        fitButton.isHidden = !(session.isPortrait && scale > 1.01)
        if abs(session.zoomScale - scale) > 0.001 {
            let wasZoomed = session.isZoomed
            session.zoomScale = scale
            if wasZoomed != session.isZoomed { relayoutBar() }
        }
        updateAccessibilityValue()
    }

    private func clampOffset() {
        let size = canvas.bounds.size
        let video = videoRect(in: size)
        let maxX = max(0, (video.width * scale - size.width) / 2)
        let maxY = max(0, (video.height * scale - size.height) / 2)
        offset.x = min(max(offset.x, -maxX), maxX)
        offset.y = min(max(offset.y, -maxY), maxY)
    }

    private func canvasPoint(_ location: CGPoint) -> CGPoint {
        view.convert(location, to: canvas)
    }

    private func resetZoomAnimated() {
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
            self.scale = 1
            self.offset = .zero
            self.layoutContent()
        }
    }

    /// Trackpad: keeps the pointer in view while zoomed.
    private func followPointer() {
        guard scale > 1.01 else { return }
        let size = canvas.bounds.size
        let video = videoRect(in: size)
        let inContent = CGPoint(x: video.minX + pointer.x * video.width - size.width / 2,
                                y: video.minY + pointer.y * video.height - size.height / 2)
        let onScreen = CGPoint(x: size.width / 2 + offset.x + inContent.x * scale, y: size.height / 2 + offset.y + inContent.y * scale)
        let margin: CGFloat = 40
        if onScreen.x < margin { offset.x += margin - onScreen.x }
        if onScreen.x > size.width - margin { offset.x -= onScreen.x - (size.width - margin) }
        if onScreen.y < margin { offset.y += margin - onScreen.y }
        if onScreen.y > size.height - margin { offset.y -= onScreen.y - (size.height - margin) }
    }

    // MARK: Pointer and buttons

    private func sendPointer() {
        let x = Int((pointer.x * streamSize.width).rounded())
        let y = Int((pointer.y * streamSize.height).rounded())
        input.movePointer(x: min(x, Int(streamSize.width) - 1), y: min(y, Int(streamSize.height) - 1),
                          width: Int(streamSize.width), height: Int(streamSize.height))
    }

    private func pressModifiers(_ modifiers: [Modifier]) {
        var flags: UInt8 = 0
        for modifier in modifiers {
            flags |= modifier.flag
            input.setKey(modifier.keyCode, down: true, modifiers: flags)
        }
    }

    private func releaseModifiers(_ modifiers: [Modifier]) {
        var flags = modifiers.reduce(UInt8(0)) { $0 | $1.flag }
        for modifier in modifiers.reversed() {
            flags &= ~modifier.flag
            input.setKey(modifier.keyCode, down: false, modifiers: flags)
        }
    }

    /// A button, with the key row's held modifiers around it (Ctrl+click).
    func setButton(_ button: MouseButton, down: Bool) {
        if down {
            let modifiers = session.activeModifiers
            buttonModifiers[button] = modifiers
            pressModifiers(modifiers)
            input.setButton(button.moonlight, down: true)
        } else {
            input.setButton(button.moonlight, down: false)
            releaseModifiers(buttonModifiers[button] ?? [])
            buttonModifiers[button] = nil
            session.releaseLatchedModifiers()
        }
        updateAccessibilityValue()
    }

    // MARK: Keys

    private func sendKey(_ keyCode: UInt16) {
        input.keyStroke(keyCode, modifiers: session.activeModifierFlags, nonNormalized: false)
    }

    /// Text from the iOS keyboard, with the key row's held modifiers.
    private func typed(_ text: String) {
        type(text, modifiers: session.activeModifierFlags)
        session.releaseLatchedModifiers()
        updateAccessibilityValue()
    }

    /// Characters as key strokes where a US layout has a key for them (Shift for capitals and
    /// shifted punctuation): Windows' sign-in screen, UAC and Ctrl+Alt+Del screens take only
    /// keys, not Unicode text. The rest (accents, emoji) goes as Unicode text.
    private func type(_ text: String, modifiers: UInt8) {
        var unicode = ""
        func flush() {
            if !unicode.isEmpty { input.text(unicode) }
            unicode = ""
        }
        for character in text {
            if character.isNewline {
                flush()
                input.keyStroke(KeyCode.enter, modifiers: modifiers, nonNormalized: false)
                continue
            }
            let units = Array(String(character).utf16)
            if units.count == 1 {
                let event = KeyboardSupport.translateKeyEvent(units[0], with: [])
                if event.keycode != 0 {
                    flush()
                    input.keyStroke(event.keycode, modifiers: modifiers | event.modifier, nonNormalized: true)
                    continue
                }
            }
            unicode.append(character)
        }
        flush()
    }

    private func setKeyboard(_ shown: Bool) {
        if shown {
            keyCapture.becomeFirstResponder()
        } else {
            keyCapture.resignFirstResponder()
            contentView.becomeFirstResponder()
        }
        session.keyboardShown = shown
        relayoutBar()
        updateAccessibilityValue()
    }

    @objc private func keyboardChanged(_ notification: Notification) {
        let shown = keyCapture.isFirstResponder
        if session.keyboardShown != shown {
            session.keyboardShown = shown
            relayoutBar()
            updateAccessibilityValue()
        }
    }

    private func makeKeyRow() -> UIView {
        let host = UIHostingController(rootView: KeyRow(session: session).artemisFont(.body))
        host.view.backgroundColor = .clear
        let container = UIInputView(frame: CGRect(x: 0, y: 0, width: 400, height: 54), inputViewStyle: .keyboard)
        container.allowsSelfSizing = false
        container.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: container.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        keyRowHost = host
        return container
    }

    private var keyRowHost: UIViewController?

    // MARK: Control bar

    /// Sizes the bar again after its content changed. SwiftUI updates the content on its next
    /// pass, so it's measured again then too.
    private func relayoutBar() {
        let layout = { [weak self] in
            guard let self else { return }
            self.barHost.view.invalidateIntrinsicContentSize()
            self.view.setNeedsLayout()
            UIView.animate(withDuration: 0.25, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.view.layoutIfNeeded()
            }
        }
        layout()
        DispatchQueue.main.async(execute: layout)
    }

    private func makeActions() -> DesktopSession.Actions {
        var actions = DesktopSession.Actions()
        actions.toggleKeyboard = { [weak self] in
            guard let self else { return }
            self.setKeyboard(!self.session.keyboardShown)
        }
        actions.setMode = { [weak self] mode in
            self?.session.mode = mode
            self?.haptic(.light)
            self?.relayoutBar()
            self?.updateAccessibilityValue()
        }
        actions.rightClick = { [weak self] in
            self?.click(.right)
            self?.haptic(.medium)
        }
        actions.resetZoom = { [weak self] in self?.resetZoomAnimated() }
        actions.shortcut = { [weak self] shortcut in
            self?.input.keyStroke(shortcut.keyCode, modifiers: shortcut.flags, nonNormalized: false)
            self?.haptic(.light)
            self?.updateAccessibilityValue()
        }
        actions.typeClipboard = { [weak self] in
            // As keys too, so a copied password works on the sign-in screen
            if let text = UIPasteboard.general.string, !text.isEmpty {
                self?.type(text, modifiers: 0)
                self?.updateAccessibilityValue()
            }
        }
        actions.key = { [weak self] code in
            guard let self else { return }
            self.sendKey(code)
            self.session.releaseLatchedModifiers()
            self.updateAccessibilityValue()
        }
        actions.disconnect = { [weak self] in
            self?.stopMomentum()
            self?.setKeyboard(false)
            self?.onDisconnect?()
        }
        actions.moveBar = { [weak self] translation in
            guard let self else { return }
            let bounds = self.view.bounds
            let start = self.barDragStart ?? CGPoint(x: self.barHost.view.center.x / bounds.width, y: self.barHost.view.center.y / bounds.height)
            self.barDragStart = start
            self.barCenter = CGPoint(x: start.x + translation.width / bounds.width, y: start.y + translation.height / bounds.height)
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }
        actions.endMoveBar = { [weak self] in
            guard let self else { return }
            self.barDragStart = nil
            // Remember where it ended up (clamped inside the screen)
            let bounds = self.view.bounds
            self.barCenter = CGPoint(x: self.barHost.view.center.x / bounds.width, y: self.barHost.view.center.y / bounds.height)
            UserDefaults.standard.set(NSCoder.string(for: self.barCenter), forKey: "ArtemisBarCenter")
        }
        actions.setBarExpanded = { [weak self] expanded in
            self?.session.barExpanded = expanded
            self?.relayoutBar()
            self?.updateAccessibilityValue()
        }
        return actions
    }

    // MARK: UI tests

    func updateAccessibilityValue() {
        var lines = [String(format: "zoom %.2f · %@ · keyboard %@ · bar %@", scale, session.mode.rawValue,
                            session.keyboardShown ? "on" : "off", session.barExpanded ? "open" : "folded")]
        if let events = recordedEvents?() {
            lines.append("events \(events.count)")
            lines.append(contentsOf: events.suffix(60))
        }
        canvas.accessibilityValue = lines.joined(separator: "\n")
    }

    // MARK: Status bar, orientation

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { false }

    /// A small arrow pointer for the demo desktop.
    static let cursorImage: UIImage = {
        let size = CGSize(width: 20, height: 30)
        return UIGraphicsImageRenderer(size: size).image { context in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 1.5, y: 1.5))
            path.addLine(to: CGPoint(x: 1.5, y: 24))
            path.addLine(to: CGPoint(x: 7, y: 18.5))
            path.addLine(to: CGPoint(x: 11, y: 27.5))
            path.addLine(to: CGPoint(x: 14.5, y: 26))
            path.addLine(to: CGPoint(x: 10.5, y: 17.5))
            path.addLine(to: CGPoint(x: 18, y: 17.5))
            path.close()
            UIColor.white.setFill()
            path.fill()
            UIColor.black.setStroke()
            path.lineWidth = 1.5
            path.lineJoinStyle = .round
            path.stroke()
        }
    }()
}

// MARK: - Gestures

extension DesktopViewController: TouchInterpreterDelegate {
    func pointerMode(onTrackpadArea: Bool) -> PointerMode {
        onTrackpadArea ? .trackpad : session.mode
    }

    var isZoomed: Bool { scale > 1.01 }

    func movePointer(by delta: CGVector, interval: TimeInterval) {
        // Acceleration: slow movements are precise, fast ones go far
        let speed = hypot(delta.dx, delta.dy) / max(interval, 1.0 / 240)
        let t = min(max((speed - 60) / 840, 0), 1)
        let gain = pointerSettings.pointerSpeed * (0.8 + 1.7 * t * t * (3 - 2 * t))
        // A finger's travel of 560 points crosses the desktop at the base speed; zoomed in, it's finer
        let reference: CGFloat = 560
        let aspect = streamSize.width / streamSize.height
        pointer.x = min(max(pointer.x + delta.dx * gain / (reference * scale), 0), 1)
        pointer.y = min(max(pointer.y + delta.dy * gain * aspect / (reference * scale), 0), 1)
        sendPointer()
        followPointer()
        layoutContent()
    }

    func movePointer(to desktop: CGPoint) {
        pointer = CGPoint(x: min(max(desktop.x, 0), 1), y: min(max(desktop.y, 0), 1))
        sendPointer()
        layoutContent()
    }

    func desktopPoint(at location: CGPoint) -> CGPoint? {
        let inCanvas = canvasPoint(location)
        guard canvas.bounds.contains(inCanvas) else { return nil }
        let inContent = contentView.convert(location, from: view)
        let video = videoRect(in: contentView.bounds.size)
        return CGPoint(x: min(max((inContent.x - video.minX) / video.width, 0), 1),
                       y: min(max((inContent.y - video.minY) / video.height, 0), 1))
    }

    func click(_ button: MouseButton) {
        let modifiers = session.activeModifiers
        pressModifiers(modifiers)
        input.click(button.moonlight)
        releaseModifiers(modifiers)
        session.releaseLatchedModifiers()
        updateAccessibilityValue()
    }

    func scroll(by delta: CGVector) {
        var delta = delta
        // Mostly vertical or mostly horizontal: keep to that axis
        if abs(delta.dx) < abs(delta.dy) * 0.5 { delta.dx = 0 }
        if abs(delta.dy) < abs(delta.dx) * 0.5 { delta.dy = 0 }
        // 120 is one wheel notch: one per ~24 points. Natural scrolling: the content follows the fingers
        let direction: CGFloat = pointerSettings.naturalScrolling ? 1 : -1
        scrollRemainder.dy += delta.dy * 5 * direction
        scrollRemainder.dx += -delta.dx * 5 * direction
        let vertical = Int(scrollRemainder.dy)
        let horizontal = Int(scrollRemainder.dx)
        guard vertical != 0 || horizontal != 0 else { return }
        scrollRemainder.dy -= CGFloat(vertical)
        scrollRemainder.dx -= CGFloat(horizontal)
        input.scroll(vertical: vertical, horizontal: horizontal)
        updateAccessibilityValue()
    }

    func startMomentum(velocity: CGVector) {
        momentumVelocity = velocity
        lastMomentumTime = CACurrentMediaTime()
        if momentumLink == nil {
            // Through a weak proxy: a display link keeps its target alive
            let link = CADisplayLink(target: WeakTarget(self), selector: #selector(WeakTarget.momentumStep))
            link.add(to: .main, forMode: .common)
            momentumLink = link
        }
    }

    @objc fileprivate func momentumStep(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let interval = min(now - lastMomentumTime, 0.05)
        lastMomentumTime = now
        momentumVelocity.dx *= pow(0.93, interval * 60)
        momentumVelocity.dy *= pow(0.93, interval * 60)
        if hypot(momentumVelocity.dx, momentumVelocity.dy) < 40 {
            stopMomentum()
            return
        }
        scroll(by: CGVector(dx: momentumVelocity.dx * interval, dy: momentumVelocity.dy * interval))
    }

    func stopMomentum() {
        momentumLink?.invalidate()
        momentumLink = nil
    }

    func zoom(by factor: CGFloat, around location: CGPoint) {
        let anchor = canvasPoint(location)
        let size = canvas.bounds.size
        let newScale = min(max(scale * factor, 1), 5)
        // Keep the desktop point under the fingers where it is
        let center = CGPoint(x: size.width / 2 + offset.x, y: size.height / 2 + offset.y)
        let inContent = CGPoint(x: (anchor.x - center.x) / scale, y: (anchor.y - center.y) / scale)
        let newCenter = CGPoint(x: anchor.x - inContent.x * newScale, y: anchor.y - inContent.y * newScale)
        scale = newScale
        offset = CGPoint(x: newCenter.x - size.width / 2, y: newCenter.y - size.height / 2)
        layoutContent()
    }

    func pan(by delta: CGVector) {
        offset.x += delta.dx
        offset.y += delta.dy
        layoutContent()
    }

    func resetZoom() {
        resetZoomAnimated()
    }

    func toggleKeyboard() {
        setKeyboard(!session.keyboardShown)
    }

    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    fileprivate func touches(_ touches: Set<UITouch>, phase: UITouch.Phase) {
        let onArea = touches.first.map { $0.view === trackpadArea || $0.view?.isDescendant(of: trackpadArea) == true } ?? false
        let samples = touches.filter { $0.type == .direct }.map { touch in
            let location = touch.location(in: view)
            return TouchSample(id: ObjectIdentifier(touch), location: location,
                               desktop: onArea ? nil : desktopPoint(at: location), time: touch.timestamp)
        }
        guard !samples.isEmpty else { return }
        switch phase {
        case .began: interpreter.began(samples, onTrackpadArea: onArea)
        case .moved: interpreter.moved(samples)
        case .ended: interpreter.ended(samples)
        default:
            stopMomentum()
            interpreter.cancelled()
        }
    }
}

/// Takes the finger touches of the desktop view and the trackpad area.
@objc(DesktopTouchHandler)
final class DesktopTouchHandler: UIResponder {
    private weak var controller: DesktopViewController?

    init(controller: DesktopViewController) {
        self.controller = controller
        super.init()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        controller?.touches(touches, phase: .began)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        controller?.touches(touches, phase: .moved)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        controller?.touches(touches, phase: .ended)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        controller?.touches(touches, phase: .cancelled)
    }
}

/// The canvas around the desktop view: touches on it (outside a zoomed-out desktop) count too.
final class DesktopCanvasView: UIView {
    weak var touchHandler: DesktopTouchHandler?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { touchHandler?.touchesBegan(touches, with: event) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { touchHandler?.touchesMoved(touches, with: event) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { touchHandler?.touchesEnded(touches, with: event) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touchHandler?.touchesCancelled(touches, with: event) }
}

/// Upright, under the desktop: a trackpad with left and right buttons.
final class TrackpadAreaView: UIView {
    weak var touchHandler: DesktopTouchHandler?
    var onButton: ((MouseButton, Bool) -> Void)?
    private let hint = UILabel()
    private let icon = UIImageView(image: UIImage(systemName: "rectangle.and.hand.point.up.left"))
    private let left = UIButton(configuration: .glass())
    private let right = UIButton(configuration: .glass())

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 26
        layer.cornerCurve = .continuous
        isAccessibilityElement = false
        accessibilityIdentifier = "trackpad"

        icon.tintColor = .tertiaryLabel
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30, weight: .light)
        hint.text = "Trackpad"
        hint.textColor = .tertiaryLabel
        hint.textAlignment = .center
        hint.adjustsFontForContentSizeCategory = false
        addSubview(icon)
        addSubview(hint)

        for (button, title, which) in [(left, "Left", MouseButton.left), (right, "Right", MouseButton.right)] {
            var configuration = UIButton.Configuration.glass()
            configuration.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: Typography.uiFont(.subheadline, sizeCategory: .large)]))
            configuration.baseForegroundColor = .label
            button.configuration = configuration
            button.accessibilityLabel = "\(title) Click"
            button.accessibilityIdentifier = "trackpad.\(which.name)"
            button.addAction(UIAction { [weak self] _ in self?.onButton?(which, true) }, for: .touchDown)
            button.addAction(UIAction { [weak self] _ in self?.onButton?(which, false) }, for: [.touchUpInside, .touchUpOutside, .touchCancel])
            addSubview(button)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        hint.font = Typography.uiFont(.footnote, sizeCategory: .large)
        let buttonHeight: CGFloat = bounds.height > 170 ? 56 : 0
        let gap: CGFloat = 8
        let inset: CGFloat = 10
        let half = (bounds.width - inset * 2 - gap) / 2
        left.isHidden = buttonHeight == 0
        right.isHidden = buttonHeight == 0
        left.frame = CGRect(x: inset, y: bounds.height - inset - buttonHeight, width: half, height: buttonHeight)
        right.frame = CGRect(x: inset + half + gap, y: left.frame.minY, width: half, height: buttonHeight)
        let padTop = bounds.minY
        let padBottom = buttonHeight > 0 ? left.frame.minY : bounds.maxY
        let mid = (padTop + padBottom) / 2
        icon.frame = CGRect(x: bounds.midX - 24, y: mid - 30, width: 48, height: 36)
        hint.frame = CGRect(x: 0, y: mid + 10, width: bounds.width, height: 22)
        icon.isHidden = padBottom - padTop < 90
        hint.isHidden = icon.isHidden
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { touchHandler?.touchesBegan(touches, with: event) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { touchHandler?.touchesMoved(touches, with: event) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { touchHandler?.touchesEnded(touches, with: event) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touchHandler?.touchesCancelled(touches, with: event) }
}

/// Takes the iOS keyboard's typing (and a hardware keyboard's keys while it's up).
final class KeyCaptureView: UIView, UIKeyInput {
    var onText: ((String) -> Void)?
    var onDelete: (() -> Void)?
    var onHardwareKey: ((UIPress, Bool) -> Bool)?
    var accessory: UIView?

    override var canBecomeFirstResponder: Bool { true }
    override var inputAccessoryView: UIView? { accessory }

    var hasText: Bool { true }
    func insertText(_ text: String) { onText?(text) }
    func deleteBackward() { onDelete?() }

    // Plain typing: no corrections, capitals or smart punctuation
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var inlinePredictionType: UITextInlinePredictionType = .no
    var keyboardType: UIKeyboardType = .default
    var returnKeyType: UIReturnKeyType = .default

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let handled = presses.map { onHardwareKey?($0, true) ?? false }.contains(true)
        if !handled { super.pressesBegan(presses, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let handled = presses.map { onHardwareKey?($0, false) ?? false }.contains(true)
        if !handled { super.pressesEnded(presses, with: event) }
    }

    // Leaving the app mid-press: the keys come up on the PC too
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let handled = presses.map { onHardwareKey?($0, false) ?? false }.contains(true)
        if !handled { super.pressesCancelled(presses, with: event) }
    }
}

/// Forwards the momentum display link to the controller without keeping it alive.
private final class WeakTarget: NSObject {
    weak var controller: DesktopViewController?

    init(_ controller: DesktopViewController) {
        self.controller = controller
    }

    @objc func momentumStep(_ link: CADisplayLink) {
        guard let controller else {
            link.invalidate()
            return
        }
        controller.momentumStep(link)
    }
}
