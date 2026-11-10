import Foundation

/// One colour as the design file states it: sRGB channels in 0...1, straight from a hex string.
public struct Swatch: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    /// Accepts `#RRGGBB` and `#RRGGBBAA`, with or without the hash. Anything else is nil.
    public init?(hex: String) {
        var text = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard text.count == 6 || text.count == 8, UInt32(text, radix: 16) != nil else { return nil }
        if text.count == 6 { text += "FF" }
        guard let full = UInt32(text, radix: 16) else { return nil }
        red = Double((full >> 24) & 0xFF) / 255
        green = Double((full >> 16) & 0xFF) / 255
        blue = Double((full >> 8) & 0xFF) / 255
        alpha = Double(full & 0xFF) / 255
    }

    /// The value back as the design file writes it: `#RRGGBB`, with `AA` only when translucent.
    public var hex: String {
        let channels = alpha < 1 ? [red, green, blue, alpha] : [red, green, blue]
        return "#" + channels.map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
    }

    /// Relative luminance as WCAG 2 defines it, 0 for black and 1 for white. Alpha is ignored:
    /// a translucent token is judged as if it were painted opaque.
    public var luminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The WCAG contrast ratio against another colour, 1 for the same colour up to 21 for black
    /// on white. Body text wants at least 4.5, large text and chrome at least 3.
    public func contrast(against other: Swatch) -> Double {
        let (bright, dim) = luminance > other.luminance ? (luminance, other.luminance) : (other.luminance, luminance)
        return (bright + 0.05) / (dim + 0.05)
    }
}

/// A token with one value per appearance.
public struct Tone: Equatable, Sendable {
    public var light: Swatch
    public var dark: Swatch

    init(_ light: String, _ dark: String) {
        guard let l = Swatch(hex: light), let d = Swatch(hex: dark) else {
            preconditionFailure("Palette token with a bad hex value: \(light) / \(dark)")
        }
        self.light = l
        self.dark = d
    }
}

/// The `ui-` colour tokens from the Foundations board, one per appearance. Light is the leaf
/// palette; dark is Graphite: neutral greys for the window, surfaces, lines and text, with green
/// kept for actions, selection and the lit card. `Theme` turns these into dynamic `Color`s; keep
/// every value here so the two files never drift.
public enum Palette {
    public static let amethyst = Tone("#5B2A9E", "#C3B2EE")
    public static let amethystSoft = Tone("#5B2A9E14", "#B9A6E61F")
    public static let brand = Tone("#5B2A9E", "#5B2A9E")
    public static let canvas = Tone("#EDF3E7", "#161616")
    public static let card = Tone("#CDE3C1", "#222222")
    public static let cardAgent = Tone("#E3D9F6", "#2B2445")
    public static let cardAgentInk = Tone("#3E1C70", "#DCCFF7")
    public static let cardAgentLine = Tone("#BDABE7", "#5F4D96")
    public static let cardInk = Tone("#14281B", "#EDEDEB")
    public static let cardLine = Tone("#8FB882", "#343434")
    public static let cardLit = Tone("#8CCC8C", "#5DBB68")
    public static let cardLitInk = Tone("#0E1C13", "#0B160D")
    public static let cardLitLine = Tone("#4E8A55", "#9BDDA1")
    public static let cardLitMeta = Tone("#24432B", "#1F3A23")
    public static let cardMeta = Tone("#4B6650", "#9A9A94")
    public static let cardNote = Tone("#E3E8C0", "#25241F")
    public static let cardNoteLine = Tone("#B4BF79", "#3B3930")
    public static let cardNoteMeta = Tone("#626A3C", "#A8A48F")
    public static let glass = Tone("#FFFFFFE0", "#1C1C1CE6")
    public static let glow = Tone("#8CCC8C59", "#7FCB8626")
    public static let hub = Tone("#24432B", "#262626")
    public static let hubAccent = Tone("#8CCC8C", "#8CCC8C")
    public static let hubInk = Tone("#EEF6EA", "#F2F2F0")
    public static let hubLine = Tone("#24432B", "#3A3A3A")
    public static let hubMark = Tone("#B9A6E6", "#B9A6E6")
    public static let hubMeta = Tone("#A9C7A3", "#A0A09A")
    public static let kraft = Tone("#F6EFDF", "#1F1D18")
    public static let kraftInk = Tone("#86652A", "#D9B877")
    public static let leaf = Tone("#3B7A45", "#7FCB86")
    public static let leafFill = Tone("#3F7F48", "#5DBB68")
    public static let leafGlow = Tone("#8CCC8C40", "#7FCB861F")
    public static let leafLine = Tone("#4E8A5580", "#7FCB8666")
    public static let leafSoft = Tone("#4E8A551C", "#7FCB861F")
    public static let light = Tone("#FFFFFFB3", "#FFFFFF0A")
    public static let light0 = Tone("#FFFFFF00", "#FFFFFF00")
    public static let line = Tone("#1B3A2417", "#FFFFFF14")
    public static let lineStrong = Tone("#1B3A2430", "#FFFFFF26")
    public static let lit = Tone("#DCEED3", "#1F2A21")
    public static let onLeaf = Tone("#FFFFFF", "#0B160D")
    public static let pistil = Tone("#7A4E12", "#EFC77F")
    public static let pistilSoft = Tone("#DCAC6240", "#DCAC6238")
    public static let raised = Tone("#FFFFFF", "#242424")
    public static let rose = Tone("#A23A59", "#EC9BB4")
    public static let roseSoft = Tone("#DF96B53D", "#E58AA626")
    public static let scrim = Tone("#1B2E2138", "#000000A6")
    public static let shadow = Tone("#1B2E211A", "#00000066")
    public static let shadowStrong = Tone("#1B2E2133", "#000000A6")
    public static let sidebar = Tone("#E8EFE2", "#141414")
    public static let surface = Tone("#FFFFFF", "#1A1A1A")
    public static let text = Tone("#14281B", "#EDEDEB")
    public static let text2 = Tone("#435848", "#B5B5B0")
    public static let text3 = Tone("#6C7F6E", "#85857F")
    public static let window = Tone("#F7F9F3", "#141414")

    /// Every token by the name the board gives it, so the design file's table can be checked
    /// against this one row by row.
    public static let tokens: [String: Tone] = [
        "ui-amethyst": amethyst, "ui-amethyst-soft": amethystSoft, "ui-brand": brand,
        "ui-canvas": canvas, "ui-card": card, "ui-card-agent": cardAgent,
        "ui-card-agent-ink": cardAgentInk, "ui-card-agent-line": cardAgentLine,
        "ui-card-ink": cardInk, "ui-card-line": cardLine, "ui-card-lit": cardLit,
        "ui-card-lit-ink": cardLitInk, "ui-card-lit-line": cardLitLine,
        "ui-card-lit-meta": cardLitMeta, "ui-card-meta": cardMeta, "ui-card-note": cardNote,
        "ui-card-note-line": cardNoteLine, "ui-card-note-meta": cardNoteMeta, "ui-glass": glass,
        "ui-glow": glow, "ui-hub": hub, "ui-hub-accent": hubAccent, "ui-hub-ink": hubInk,
        "ui-hub-line": hubLine, "ui-hub-mark": hubMark, "ui-hub-meta": hubMeta, "ui-kraft": kraft,
        "ui-kraft-ink": kraftInk, "ui-leaf": leaf, "ui-leaf-fill": leafFill, "ui-leaf-glow": leafGlow,
        "ui-leaf-line": leafLine, "ui-leaf-soft": leafSoft, "ui-light": light, "ui-light-0": light0,
        "ui-line": line, "ui-line-strong": lineStrong, "ui-lit": lit, "ui-on-leaf": onLeaf,
        "ui-pistil": pistil, "ui-pistil-soft": pistilSoft, "ui-raised": raised, "ui-rose": rose,
        "ui-rose-soft": roseSoft, "ui-scrim": scrim, "ui-shadow": shadow,
        "ui-shadow-strong": shadowStrong, "ui-sidebar": sidebar, "ui-surface": surface,
        "ui-text": text, "ui-text-2": text2, "ui-text-3": text3, "ui-window": window,
    ]
}

/// Corner radii. The named ones are the Foundations board's scale, one per kind of element;
/// the four sizes stay for rows and small chrome the board does not name.
public enum Radius {
    public static let sm: CGFloat = 6
    public static let md: CGFloat = 10
    public static let lg: CGFloat = 14
    public static let xl: CGFloat = 22

    public static let keycap: CGFloat = 4
    public static let chip: CGFloat = 5
    public static let iconButton: CGFloat = 7
    public static let button: CGFloat = 8
    public static let field: CGFloat = 8
    public static let segmented: CGFloat = 9
    public static let card: CGFloat = 10
    public static let toast: CGFloat = 12
    public static let detail: CGFloat = 14
    public static let hub: CGFloat = 20
    public static let sheet: CGFloat = 22
}

/// The three bundled typefaces, by family name and file.
public enum Typeface: String, CaseIterable, Sendable {
    case text = "Figtree"
    case display = "Fraunces"
    case mono = "JetBrains Mono"

    public var family: String { rawValue }

    public var file: String {
        switch self {
        case .text: return "Figtree.ttf"
        case .display: return "Fraunces.ttf"
        case .mono: return "JetBrainsMono.ttf"
        }
    }

    /// Where the font file lives in the package bundle, or nil when the resources are missing.
    public var url: URL? {
        Bundle.module.url(forResource: "Fonts/" + file, withExtension: nil)
    }
}

/// A step of the type scale: typeface, size, weight on the 100...900 axis, and tracking.
public struct TextStyle: Equatable, Sendable {
    public var typeface: Typeface
    public var size: CGFloat
    public var weight: Int
    public var tracking: CGFloat = 0
    public var uppercase = false
}

/// The type scale from the Foundations board.
public enum TextRole: CaseIterable, Sendable {
    case display, title, heading, body, cardTitle, label, caption, eyebrow, mono

    public var style: TextStyle {
        switch self {
        case .display: return TextStyle(typeface: .display, size: 34, weight: 500)
        case .title: return TextStyle(typeface: .display, size: 26, weight: 500)
        case .heading: return TextStyle(typeface: .text, size: 17, weight: 600)
        case .body: return TextStyle(typeface: .text, size: 14, weight: 400)
        case .cardTitle: return TextStyle(typeface: .text, size: 13, weight: 600)
        case .label: return TextStyle(typeface: .text, size: 12, weight: 500)
        case .caption: return TextStyle(typeface: .text, size: 11, weight: 400)
        case .eyebrow: return TextStyle(typeface: .text, size: 10, weight: 700, tracking: 1.6, uppercase: true)
        case .mono: return TextStyle(typeface: .mono, size: 12, weight: 400)
        }
    }
}
