//
//  Typography.swift
//  Artemis
//
//  The app's typeface, Orbix (Artemis/Fonts, SIL Open Font License), with SF Pro for the
//  characters it lacks (`:` `;` `·` `…` brackets, `+ % = * < >`, accents and other symbols)
//  and for digits, at a matching size and weight, through the font's cascade list. If the font can't be
//  loaded, everything uses the system font at the usual sizes.
//
//  Sizes follow the Dynamic Type text styles (UIFontMetrics), a little smaller than SF's,
//  because Orbix is wider with a taller x-height. Its line height (1.4 em) is already
//  generous, so text needs no extra line spacing.
//

import SwiftUI
import UIKit

enum Typography {
    static let postScriptName = "Orbix-Regular"

    /// Registers the bundled font, if the build has it. Call once at launch.
    static func register() {
        guard !registered else { return }
        registered = true
        let urls = ["Fonts/", ""].compactMap {
            Bundle.main.url(forResource: $0 + "Orbix-Regular", withExtension: "otf")
        }
        if let url = urls.first {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                logInfo("Orbix not registered: \(String(describing: error?.takeRetainedValue()))")
            }
        }
        isAvailable = UIFont(name: postScriptName, size: 12) != nil
        logInfo(isAvailable ? "Using Orbix" : "Orbix not bundled; using the system font")
    }

    private static var registered = false
    /// Whether the build has the font (false: the system font everywhere).
    private(set) static var isAvailable = false

    /// A text style's role in the app.
    enum Style {
        case largeTitle, title, title2, title3, headline, body, bodyEmphasized, callout, subheadline, footnote, caption, caption2
        /// A large number on its own (the pairing PIN).
        case display(CGFloat)

        var textStyle: UIFont.TextStyle {
            switch self {
            case .largeTitle: .largeTitle
            case .title: .title1
            case .title2: .title2
            case .title3: .title3
            case .headline: .headline
            case .body, .bodyEmphasized: .body
            case .callout: .callout
            case .subheadline: .subheadline
            case .footnote: .footnote
            case .caption: .caption1
            case .caption2: .caption2
            case .display: .largeTitle
            }
        }

        /// The size at the default text size (Large).
        var systemSize: CGFloat {
            switch self {
            case .largeTitle: 34
            case .title: 28
            case .title2: 22
            case .title3: 20
            case .headline, .body, .bodyEmphasized: 17
            case .callout: 16
            case .subheadline: 15
            case .footnote: 13
            case .caption: 12
            case .caption2: 11
            case .display(let size): size
            }
        }

        /// SF Pro's weight: for the system font, and for the characters Orbix lacks
        /// (its strokes are about as heavy as SF's regular to medium).
        var weight: UIFont.Weight {
            switch self {
            case .largeTitle, .title: .bold
            case .headline, .bodyEmphasized, .title2, .title3: .semibold
            case .display: .bold
            default: Typography.isAvailable ? .medium : .regular
            }
        }

        /// The largest Orbix size at the accessibility text sizes: Orbix is wide, and at SF's
        /// sizes words no longer fit a row and break in the middle. (Its tall x-height makes
        /// these read about as large as SF's 15% bigger.)
        var maximumSize: CGFloat {
            switch self {
            case .largeTitle: 40
            case .title: 36
            case .title2, .title3: 33
            case .headline, .body, .bodyEmphasized: 31
            case .callout, .subheadline: 28
            case .footnote, .caption: 25
            case .caption2: 22
            case .display(let size): size
            }
        }

        /// Orbix's size relative to SF's for the same role.
        var customScale: CGFloat {
            switch self {
            case .largeTitle, .title, .display: 0.88
            case .caption, .caption2, .footnote: 0.94
            default: 0.9
            }
        }

        /// Extra letter spacing in points, at the default size: small text opens up,
        /// big titles close up a little.
        var customTracking: CGFloat {
            switch self {
            case .largeTitle, .title, .display: -0.3
            case .caption, .caption2, .footnote: 0.4
            case .subheadline, .callout: 0.2
            default: 0.1
            }
        }
    }

    /// The font for a style at a content size, scaled like the matching text style.
    static func uiFont(_ style: Style, sizeCategory: UIContentSizeCategory? = nil) -> UIFont {
        let traits = sizeCategory.map { UITraitCollection(preferredContentSizeCategory: $0) }
        let metrics = UIFontMetrics(forTextStyle: style.textStyle)
        guard isAvailable, let orbix = UIFont(name: postScriptName, size: 17) else {
            let base = UIFont.systemFont(ofSize: style.systemSize, weight: style.weight)
            if case .display = style { return base }
            return metrics.scaledFont(for: base, compatibleWith: traits)
        }
        var size = style.systemSize * style.customScale
        if case .display = style {} else {
            size = min(metrics.scaledValue(for: size, compatibleWith: traits), style.maximumSize)
        }
        // Orbix draws the letters and punctuation it has; SF Pro draws the rest, digits included
        // (Orbix's 1 reads as a 7, which won't do for addresses, resolutions and PINs)
        let fallback = UIFont.systemFont(ofSize: size, weight: style.weight).fontDescriptor
        let descriptor = orbix.fontDescriptor.addingAttributes([
            .characterSet: orbixCharacters,
            .cascadeList: [fallback],
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    /// The characters Orbix draws: its own, without the digits.
    private static let orbixCharacters: CharacterSet = {
        var set = CTFontCopyCharacterSet(UIFont(name: postScriptName, size: 17)! as CTFont) as CharacterSet
        set.remove(charactersIn: "0123456789")
        return set
    }()

    /// Letter spacing for a style, scaled with the text.
    static func tracking(_ style: Style, sizeCategory: UIContentSizeCategory? = nil) -> CGFloat {
        guard isAvailable else { return 0 }
        let traits = sizeCategory.map { UITraitCollection(preferredContentSizeCategory: $0) }
        return UIFontMetrics(forTextStyle: style.textStyle).scaledValue(for: style.customTracking, compatibleWith: traits)
    }

    /// Navigation bar titles, large and inline.
    static func styleNavigationBars() {
        let category = UIApplication.shared.preferredContentSizeCategory
        let large = uiFont(.largeTitle, sizeCategory: category)
        let inline = uiFont(.headline, sizeCategory: category)
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: large, .kern: tracking(.largeTitle, sizeCategory: category)]
        // Inline titles are centred: no tracking, which would also follow the last letter and
        // nudge the title off centre (Orbix's side bearings are even, 50/50 units)
        bar.titleTextAttributes = [.font: inline]
        UISegmentedControl.appearance().setTitleTextAttributes([.font: uiFont(.subheadline, sizeCategory: category)], for: .normal)
    }
}

/// Bridges for the Obj-C stream screen.
@objc(ArtemisTypography)
final class ArtemisTypography: NSObject {
    @objc static func headlineFont() -> UIFont { Typography.uiFont(.headline) }
    @objc static func bodyFont() -> UIFont { Typography.uiFont(.subheadline) }
    @objc static func captionFont() -> UIFont { Typography.uiFont(.caption) }
}

extension DynamicTypeSize {
    var contentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}

private struct ArtemisFontModifier: ViewModifier {
    let style: Typography.Style
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        let category = typeSize.contentSizeCategory
        content
            .font(Font(Typography.uiFont(style, sizeCategory: category)))
            .tracking(Typography.tracking(style, sizeCategory: category))
    }
}

extension View {
    /// The app's typeface in a text style's role, following Dynamic Type.
    func artemisFont(_ style: Typography.Style) -> some View {
        modifier(ArtemisFontModifier(style: style))
    }
}
