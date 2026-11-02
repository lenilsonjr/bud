#if canImport(SwiftUI)
import SwiftUI
#if canImport(CoreText)
import CoreText
#endif

/// Every colour, font and radius a view may use. Values come from `Palette`; this file only
/// turns them into SwiftUI types that follow the system appearance.
enum Theme {
    // Surfaces
    static let window = Color(Palette.window)
    static let canvas = Color(Palette.canvas)
    static let sidebar = Color(Palette.sidebar)
    static let surface = Color(Palette.surface)
    static let raised = Color(Palette.raised)
    static let glass = Color(Palette.glass)
    static let scrim = Color(Palette.scrim)
    static let kraft = Color(Palette.kraft)

    // Cards
    static let card = Color(Palette.card)
    static let cardLine = Color(Palette.cardLine)
    static let cardInk = Color(Palette.cardInk)
    static let cardMeta = Color(Palette.cardMeta)
    static let cardNote = Color(Palette.cardNote)
    static let cardNoteLine = Color(Palette.cardNoteLine)
    static let cardNoteMeta = Color(Palette.cardNoteMeta)
    static let cardAgent = Color(Palette.cardAgent)
    static let cardAgentLine = Color(Palette.cardAgentLine)
    static let cardAgentInk = Color(Palette.cardAgentInk)
    static let cardLit = Color(Palette.cardLit)
    static let cardLitLine = Color(Palette.cardLitLine)
    static let cardLitInk = Color(Palette.cardLitInk)
    static let cardLitMeta = Color(Palette.cardLitMeta)
    static let lit = Color(Palette.lit)

    // The hub
    static let hub = Color(Palette.hub)
    static let hubLine = Color(Palette.hubLine)
    static let hubInk = Color(Palette.hubInk)
    static let hubMeta = Color(Palette.hubMeta)
    static let hubAccent = Color(Palette.hubAccent)
    static let hubMark = Color(Palette.hubMark)

    // Text and lines
    static let text = Color(Palette.text)
    static let text2 = Color(Palette.text2)
    static let text3 = Color(Palette.text3)
    static let line = Color(Palette.line)
    static let lineStrong = Color(Palette.lineStrong)

    // Accents
    static let leaf = Color(Palette.leaf)
    static let leafFill = Color(Palette.leafFill)
    static let leafSoft = Color(Palette.leafSoft)
    static let leafLine = Color(Palette.leafLine)
    static let leafGlow = Color(Palette.leafGlow)
    static let onLeaf = Color(Palette.onLeaf)
    static let amethyst = Color(Palette.amethyst)
    static let amethystSoft = Color(Palette.amethystSoft)
    static let brand = Color(Palette.brand)
    static let pistil = Color(Palette.pistil)
    static let pistilSoft = Color(Palette.pistilSoft)
    static let kraftInk = Color(Palette.kraftInk)
    static let rose = Color(Palette.rose)
    static let roseSoft = Color(Palette.roseSoft)

    // Depth and the lamp
    static let shadow = Color(Palette.shadow)
    static let shadowStrong = Color(Palette.shadowStrong)
    static let glow = Color(Palette.glow)
    static let light = Color(Palette.light)
    static let light0 = Color(Palette.light0)

    /// The font for a step of the type scale. Registers the bundled typefaces on first use.
    static func font(_ role: TextRole) -> Font {
        let style = role.style
        _ = FontLoader.registered
        return Font.custom(style.typeface.family, size: style.size).weight(weight(style.weight))
    }

    /// Kerning for a step of the type scale; only the eyebrow has any.
    static func tracking(_ role: TextRole) -> CGFloat { role.style.tracking }

    static func light(for role: CardRole) -> Double {
        switch role {
        case .center, .ring: return 1
        case .deep: return 0.85
        case .ghost: return 0.7
        case .kin: return 0.55
        }
    }

    private static func weight(_ axis: Int) -> Font.Weight {
        switch axis {
        case ..<200: return .thin
        case ..<300: return .ultraLight
        case ..<400: return .light
        case ..<500: return .regular
        case ..<600: return .medium
        case ..<700: return .semibold
        case ..<800: return .bold
        case ..<900: return .heavy
        default: return .black
        }
    }
}

extension Color {
    /// A colour that resolves per appearance, so the app follows the system setting.
    init(_ tone: Tone) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            UIColor(traits.userInterfaceStyle == .dark ? tone.dark : tone.light)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(dark ? tone.dark : tone.light)
        })
        #else
        self.init(red: tone.light.red, green: tone.light.green, blue: tone.light.blue, opacity: tone.light.alpha)
        #endif
    }
}

#if canImport(UIKit)
import UIKit
extension UIColor {
    convenience init(_ swatch: Swatch) {
        self.init(red: swatch.red, green: swatch.green, blue: swatch.blue, alpha: swatch.alpha)
    }
}
#elseif canImport(AppKit)
import AppKit
extension NSColor {
    convenience init(_ swatch: Swatch) {
        self.init(srgbRed: swatch.red, green: swatch.green, blue: swatch.blue, alpha: swatch.alpha)
    }
}
#endif

/// Registers the bundled typefaces for this process once, so the package, the apps and the
/// runner all draw with the same files and no target needs a plist entry.
enum FontLoader {
    static let registered: Bool = {
        #if canImport(CoreText)
        for face in Typeface.allCases {
            guard let url = face.url else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        #endif
        return true
    }()
}

extension View {
    /// Applies a step of the type scale: font, tracking and case.
    func textRole(_ role: TextRole) -> some View {
        font(Theme.font(role))
            .tracking(Theme.tracking(role))
            .textCase(role.style.uppercase ? .uppercase : nil)
    }
}
#endif
