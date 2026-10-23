//
//  KeyRow.swift
//  Artemis
//
//  The keys above the iOS keyboard (its input accessory): Esc, Tab, the sticky modifiers,
//  arrows and editing keys, and a page of function keys. Fn stays put at the start while the
//  others scroll sideways. A key lights up and fires only on a real tap: a finger that lands on
//  a key and swipes the row along scrolls it instead (the scroll view delays and cancels the
//  key's touch, as UIKit's own scroll views do). Swiping down on the row drags the keyboard
//  down with the finger and closes it, as in Messages: the row sits in a vertical scroll view
//  with UIKit's interactive keyboard dismissal (keyboardDismissMode .interactive).
//

import UIKit

final class KeyRowView: UIInputView {
    private let session: DesktopSession
    private let pageButton = KeyButton(identifier: "key.page")
    /// Holds the row; dragging it down takes the keyboard down (its content stays put).
    private let dismissView = KeyScrollView()
    private let scrollView = KeyScrollView()
    private var keys: [KeyButton] = []
    private var shownPage: DesktopSession.KeyPage?
    /// For the UI tests: how many times a key lit up, the one lit now, and how far the last
    /// swipe down took the keyboard (the row's drop on screen).
    private(set) var highlightCount = 0
    private(set) var highlightedKey: String?
    private(set) var pulledDistance: CGFloat = 0
    private var pullStart: CGFloat?
    private let touchDown = TouchDownRecorder()
    var onHighlightChange: (() -> Void)?

    init(session: DesktopSession) {
        self.session = session
        super.init(frame: CGRect(x: 0, y: 0, width: 400, height: 54), inputViewStyle: .keyboard)
        allowsSelfSizing = false
        backgroundColor = .clear
        accessibilityIdentifier = "keyrow"

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = true
        // A touch on a key waits a moment to see whether it's a swipe (delaysContentTouches),
        // and a swipe takes it back from the key (touchesShouldCancel)
        scrollView.delaysContentTouches = true
        scrollView.canCancelContentTouches = true
        // Keys slide under the edges, not over Fn
        scrollView.clipsToBounds = true

        dismissView.showsVerticalScrollIndicator = false
        dismissView.showsHorizontalScrollIndicator = false
        dismissView.alwaysBounceVertical = true
        dismissView.alwaysBounceHorizontal = false
        dismissView.keyboardDismissMode = .interactive
        // The keys' own scroll view already holds a touch back to see whether it's a swipe
        dismissView.delaysContentTouches = false
        dismissView.canCancelContentTouches = true
        dismissView.clipsToBounds = false
        dismissView.delegate = self
        addSubview(dismissView)
        dismissView.addSubview(scrollView)
        dismissView.panGestureRecognizer.addTarget(self, action: #selector(pulled(_:)))
        dismissView.addGestureRecognizer(touchDown)

        dismissView.addSubview(pageButton)
        pageButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.session.keyPage = self.session.keyPage == .main ? .function : .main
        }, for: .primaryActionTriggered)
        watch(pageButton)
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Measures how far the keyboard follows the finger (UIKit moves it, the row with it).
    @objc private func pulled(_ pan: UIPanGestureRecognizer) {
        let y = convert(CGPoint.zero, to: nil).y
        switch pan.state {
        case .began:
            pullStart = y
            pulledDistance = 0
        case .changed:
            if let pullStart { pulledDistance = max(pulledDistance, y - pullStart) }
        case .ended:
            pullStart = nil
            // A quick flick down closes it too, even one too short for UIKit's own dismissal: fast
            // at the end, or fast on average since the finger came down (a flick's few touch
            // events can arrive together, leaving the pan no speed to measure)
            let distance = pan.translation(in: nil).y
            let elapsed = touchDown.downTime.map { CACurrentMediaTime() - $0 } ?? .infinity
            if (pan.velocity(in: nil).y > 600 && distance > 8) || (distance > 30 && distance / elapsed > 450) {
                DispatchQueue.main.async { [weak self] in self?.onFlickDown?() }
            }
            onHighlightChange?()
        default:
            pullStart = nil
            onHighlightChange?()
        }
    }

    /// A quick flick down on the row.
    var onFlickDown: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = bounds.height
        dismissView.frame = bounds
        dismissView.contentSize = bounds.size
        let pageWidth = pageButton.intrinsicContentSize.width
        pageButton.frame = CGRect(x: 8 + safeAreaInsets.left, y: (height - 38) / 2, width: pageWidth, height: 38)
        let scrollX = pageButton.frame.maxX + 4
        scrollView.frame = CGRect(x: scrollX, y: 0, width: max(0, bounds.width - scrollX - safeAreaInsets.right), height: height)
        // The keys side by side, 6 pt apart
        var x: CGFloat = 6
        for key in keys {
            let width = key.intrinsicContentSize.width
            key.frame = CGRect(x: x, y: (height - 38) / 2, width: width, height: 38)
            x += width + 6
        }
        scrollView.contentSize = CGSize(width: x + 2, height: height)
    }

    // MARK: Keys

    /// Shows the session's page and modifier states; called again whenever they change.
    private func update() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.update() }
        }
    }

    private func render() {
        let page = session.keyPage
        if page == .main {
            pageButton.setKey(title: "Fn", accessibility: "Function Keys")
        } else {
            pageButton.setKey(symbol: "chevron.left", accessibility: "Back to Keys")
        }
        if shownPage != page {
            shownPage = page
            for key in keys { key.removeFromSuperview() }
            keys = page == .main ? mainPage() : functionPage()
            for key in keys {
                scrollView.addSubview(key)
                watch(key)
            }
            scrollView.contentOffset = .zero
            setNeedsLayout()
            UIAccessibility.post(notification: .layoutChanged, argument: nil)
        }
        for key in keys {
            if let modifier = key.modifier {
                key.setState(session.state(of: modifier))
            }
        }
        setNeedsLayout()
    }

    private func mainPage() -> [KeyButton] {
        var keys = [
            key("Esc") { $0.actions.key(KeyCode.escape) },
            key("Tab") { $0.actions.key(KeyCode.tab) },
        ]
        for modifier in [Modifier.ctrl, .alt, .win, .shift] {
            let button = key(modifier.title) { $0.tapModifier(modifier) }
            button.modifier = modifier
            keys.append(button)
        }
        keys += [
            key(symbol: "arrow.left", "Left", "Left Arrow") { $0.actions.key(KeyCode.left) },
            key(symbol: "arrow.up", "Up", "Up Arrow") { $0.actions.key(KeyCode.up) },
            key(symbol: "arrow.down", "Down", "Down Arrow") { $0.actions.key(KeyCode.down) },
            key(symbol: "arrow.right", "Right", "Right Arrow") { $0.actions.key(KeyCode.right) },
            key("Del", accessibility: "Delete") { $0.actions.key(KeyCode.delete) },
            key("Home") { $0.actions.key(KeyCode.home) },
            key("End") { $0.actions.key(KeyCode.end) },
            key("PgUp", accessibility: "Page Up") { $0.actions.key(KeyCode.pageUp) },
            key("PgDn", accessibility: "Page Down") { $0.actions.key(KeyCode.pageDown) },
        ]
        return keys
    }

    private func functionPage() -> [KeyButton] {
        (1...12).map { number in
            key("F\(number)") { $0.actions.key(KeyCode.f1 + UInt16(number - 1)) }
        }
    }

    private func key(_ title: String, accessibility: String? = nil, action: @escaping (DesktopSession) -> Void) -> KeyButton {
        let button = KeyButton(identifier: "key.\(title)")
        button.setKey(title: title, accessibility: accessibility ?? title)
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            action(self.session)
        }, for: .primaryActionTriggered)
        return button
    }

    private func key(symbol: String, _ name: String, _ accessibility: String, action: @escaping (DesktopSession) -> Void) -> KeyButton {
        let button = KeyButton(identifier: "key.\(name)")
        button.setKey(symbol: symbol, accessibility: accessibility)
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            action(self.session)
        }, for: .primaryActionTriggered)
        return button
    }

    private func watch(_ button: KeyButton) {
        button.onHighlight = { [weak self, weak button] lit in
            guard let self, let button else { return }
            if lit {
                self.highlightCount += 1
                self.highlightedKey = button.accessibilityIdentifier
            } else if self.highlightedKey == button.accessibilityIdentifier {
                self.highlightedKey = nil
            }
            self.onHighlightChange?()
        }
    }
}

/// Notes when a finger comes down, for the flick's speed; never recognizes anything.
private final class TouchDownRecorder: UIGestureRecognizer {
    private(set) var downTime: CFTimeInterval?

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        downTime = CACurrentMediaTime()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

/// The row's scroll view: a swipe that starts on a key scrolls the row and cancels the key's
/// touch (UIScrollView keeps it for controls by default).
private final class KeyScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool { true }
}

/// One key: Liquid Glass, tinted while its modifier is held, with a lock while it's locked.
final class KeyButton: UIButton {
    var modifier: Modifier?
    var onHighlight: ((Bool) -> Void)?
    private var modifierState = DesktopSession.ModifierState.off
    private var title: String?
    private var symbol: String?
    private let lock = UIImageView(image: UIImage(systemName: "lock.fill",
                                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 8, weight: .bold)))
    private let feedback = UISelectionFeedbackGenerator()

    init(identifier: String) {
        super.init(frame: .zero)
        accessibilityIdentifier = identifier
        lock.tintColor = .white
        lock.isHidden = true
        addSubview(lock)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in
            self.restyle()
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: max(44, super.intrinsicContentSize.width), height: 38)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet {
            if isHighlighted != oldValue { onHighlight?(isHighlighted) }
        }
    }



    func setKey(title: String, accessibility: String) {
        guard self.title != title || symbol != nil else { return }
        self.title = title
        symbol = nil
        accessibilityLabel = accessibility
        restyle()
    }

    func setKey(symbol: String, accessibility: String) {
        guard self.symbol != symbol else { return }
        self.symbol = symbol
        title = nil
        accessibilityLabel = accessibility
        restyle()
    }

    func setState(_ state: DesktopSession.ModifierState) {
        guard modifierState != state else { return }
        feedback.selectionChanged()
        modifierState = state
        accessibilityValue = state == .off ? nil : (state == .locked ? "Locked" : "Held")
        lock.isHidden = state != .locked
        restyle()
    }

    private func restyle() {
        var configuration: UIButton.Configuration = modifierState == .off ? .glass() : .prominentGlass()
        configuration.baseForegroundColor = modifierState == .off ? .label : .white
        if modifierState != .off { configuration.baseBackgroundColor = .tintColor }
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10)
        configuration.cornerStyle = .fixed
        configuration.background.cornerRadius = 10
        if let symbol {
            configuration.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
            configuration.title = nil
        } else if let title {
            configuration.image = nil
            // Up to xxLarge text: the row has one line of keys
            let size = traitCollection.preferredContentSizeCategory
            let font = Typography.uiFont(.subheadline, sizeCategory: size > .extraExtraLarge ? .extraExtraLarge : size)
            let kern = Typography.tracking(.subheadline, sizeCategory: size > .extraExtraLarge ? .extraExtraLarge : size)
            configuration.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: font, .kern: kern]))
        }
        self.configuration = configuration
        invalidateIntrinsicContentSize()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        lock.frame = CGRect(x: bounds.width - 14, y: 4, width: 10, height: 10)
        bringSubviewToFront(lock)
    }
}

extension KeyRowView: UIScrollViewDelegate {
    /// The row stays in place in the keyboard while the finger takes the keyboard down.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === dismissView, scrollView.contentOffset != .zero else { return }
        scrollView.contentOffset = .zero
    }
}
