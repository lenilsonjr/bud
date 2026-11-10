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
        guard text.count == 6 || text.count == 8, text.allSatisfy(\.isHexDigit) else { return nil }
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
        return "#" + channels.map { channel in
            let byte = UInt8((channel * 255).rounded())
            return String(byte < 16 ? "0" : "") + String(byte, radix: 16, uppercase: true)
        }.joined()
    }

    /// This colour painted over an opaque one: the usual source-over blend, channel by channel.
    public func over(_ backdrop: Swatch) -> Swatch {
        var mixed = backdrop
        mixed.red = alpha * red + (1 - alpha) * backdrop.red
        mixed.green = alpha * green + (1 - alpha) * backdrop.green
        mixed.blue = alpha * blue + (1 - alpha) * backdrop.blue
        mixed.alpha = 1
        return mixed
    }

    /// Relative luminance as WCAG 2 defines it, 0 for black and 1 for white. Alpha is ignored;
    /// paint a translucent colour `over` its backdrop first.
    public var luminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The WCAG contrast ratio of this colour painted on another, 1 for the same colour up to 21
    /// for black on white. A translucent colour is blended over the other first, so a hairline
    /// is judged as the eye sees it. Body text wants at least 4.5, large text and chrome 3.
    public func contrast(against backdrop: Swatch) -> Double {
        let painted = alpha < 1 ? over(backdrop).luminance : luminance
        let (bright, dim) = painted > backdrop.luminance ? (painted, backdrop.luminance) : (backdrop.luminance, painted)
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
/// kept for actions, selection and the lit card. `Theme` turns these into dynamic `Color`s.
public enum Palette {
    /// Every token by the name the board gives it, light then dark. This table is the one place
    /// a value lives: the named statics below read from it, and a test holds it against the
    /// design file row by row.
    public static let tokens: [String: Tone] = [
        "ui-amethyst": Tone("#5B2A9E", "#C3B2EE"),
        "ui-amethyst-soft": Tone("#5B2A9E14", "#B9A6E61F"),
        "ui-brand": Tone("#5B2A9E", "#5B2A9E"),
        "ui-canvas": Tone("#EDF3E7", "#161616"),
        "ui-card": Tone("#CDE3C1", "#222222"),
        "ui-card-agent": Tone("#E3D9F6", "#2B2445"),
        "ui-card-agent-ink": Tone("#3E1C70", "#DCCFF7"),
        "ui-card-agent-line": Tone("#BDABE7", "#5F4D96"),
        "ui-card-ink": Tone("#14281B", "#EDEDEB"),
        "ui-card-line": Tone("#8FB882", "#343434"),
        "ui-card-lit": Tone("#8CCC8C", "#5DBB68"),
        "ui-card-lit-ink": Tone("#0E1C13", "#0B160D"),
        "ui-card-lit-line": Tone("#4E8A55", "#9BDDA1"),
        "ui-card-lit-meta": Tone("#24432B", "#1F3A23"),
        "ui-card-meta": Tone("#4B6650", "#9A9A94"),
        "ui-card-note": Tone("#E3E8C0", "#25241F"),
        "ui-card-note-line": Tone("#B4BF79", "#3B3930"),
        "ui-card-note-meta": Tone("#626A3C", "#A8A48F"),
        "ui-glass": Tone("#FFFFFFE0", "#1C1C1CE6"),
        "ui-glow": Tone("#8CCC8C59", "#7FCB8626"),
        "ui-hub": Tone("#24432B", "#262626"),
        "ui-hub-accent": Tone("#8CCC8C", "#8CCC8C"),
        "ui-hub-ink": Tone("#EEF6EA", "#F2F2F0"),
        "ui-hub-line": Tone("#24432B", "#3A3A3A"),
        "ui-hub-mark": Tone("#B9A6E6", "#B9A6E6"),
        "ui-hub-meta": Tone("#A9C7A3", "#A0A09A"),
        "ui-kraft": Tone("#F6EFDF", "#1F1D18"),
        "ui-kraft-ink": Tone("#86652A", "#D9B877"),
        "ui-leaf": Tone("#3B7A45", "#7FCB86"),
        "ui-leaf-fill": Tone("#3F7F48", "#5DBB68"),
        "ui-leaf-glow": Tone("#8CCC8C40", "#7FCB861F"),
        "ui-leaf-line": Tone("#4E8A5580", "#7FCB8666"),
        "ui-leaf-soft": Tone("#4E8A551C", "#7FCB861F"),
        "ui-light": Tone("#FFFFFFB3", "#FFFFFF0A"),
        "ui-light-0": Tone("#FFFFFF00", "#FFFFFF00"),
        "ui-line": Tone("#1B3A2417", "#FFFFFF14"),
        "ui-line-strong": Tone("#1B3A2430", "#FFFFFF26"),
        "ui-lit": Tone("#DCEED3", "#1F2A21"),
        "ui-on-leaf": Tone("#FFFFFF", "#0B160D"),
        "ui-pistil": Tone("#7A4E12", "#EFC77F"),
        "ui-pistil-soft": Tone("#DCAC6240", "#DCAC6238"),
        "ui-raised": Tone("#FFFFFF", "#242424"),
        "ui-rose": Tone("#A23A59", "#EC9BB4"),
        "ui-rose-soft": Tone("#DF96B53D", "#E58AA626"),
        "ui-scrim": Tone("#1B2E2138", "#000000A6"),
        "ui-shadow": Tone("#1B2E211A", "#00000066"),
        "ui-shadow-strong": Tone("#1B2E2133", "#000000A6"),
        "ui-sidebar": Tone("#E8EFE2", "#141414"),
        "ui-surface": Tone("#FFFFFF", "#1A1A1A"),
        "ui-text": Tone("#14281B", "#EDEDEB"),
        "ui-text-2": Tone("#435848", "#B5B5B0"),
        "ui-text-3": Tone("#6C7F6E", "#85857F"),
        "ui-window": Tone("#F7F9F3", "#141414"),
    ]

    public static let amethyst = token("ui-amethyst")
    public static let amethystSoft = token("ui-amethyst-soft")
    public static let brand = token("ui-brand")
    public static let canvas = token("ui-canvas")
    public static let card = token("ui-card")
    public static let cardAgent = token("ui-card-agent")
    public static let cardAgentInk = token("ui-card-agent-ink")
    public static let cardAgentLine = token("ui-card-agent-line")
    public static let cardInk = token("ui-card-ink")
    public static let cardLine = token("ui-card-line")
    public static let cardLit = token("ui-card-lit")
    public static let cardLitInk = token("ui-card-lit-ink")
    public static let cardLitLine = token("ui-card-lit-line")
    public static let cardLitMeta = token("ui-card-lit-meta")
    public static let cardMeta = token("ui-card-meta")
    public static let cardNote = token("ui-card-note")
    public static let cardNoteLine = token("ui-card-note-line")
    public static let cardNoteMeta = token("ui-card-note-meta")
    public static let glass = token("ui-glass")
    public static let glow = token("ui-glow")
    public static let hub = token("ui-hub")
    public static let hubAccent = token("ui-hub-accent")
    public static let hubInk = token("ui-hub-ink")
    public static let hubLine = token("ui-hub-line")
    public static let hubMark = token("ui-hub-mark")
    public static let hubMeta = token("ui-hub-meta")
    public static let kraft = token("ui-kraft")
    public static let kraftInk = token("ui-kraft-ink")
    public static let leaf = token("ui-leaf")
    public static let leafFill = token("ui-leaf-fill")
    public static let leafGlow = token("ui-leaf-glow")
    public static let leafLine = token("ui-leaf-line")
    public static let leafSoft = token("ui-leaf-soft")
    public static let light = token("ui-light")
    public static let light0 = token("ui-light-0")
    public static let line = token("ui-line")
    public static let lineStrong = token("ui-line-strong")
    public static let lit = token("ui-lit")
    public static let onLeaf = token("ui-on-leaf")
    public static let pistil = token("ui-pistil")
    public static let pistilSoft = token("ui-pistil-soft")
    public static let raised = token("ui-raised")
    public static let rose = token("ui-rose")
    public static let roseSoft = token("ui-rose-soft")
    public static let scrim = token("ui-scrim")
    public static let shadow = token("ui-shadow")
    public static let shadowStrong = token("ui-shadow-strong")
    public static let sidebar = token("ui-sidebar")
    public static let surface = token("ui-surface")
    public static let text = token("ui-text")
    public static let text2 = token("ui-text-2")
    public static let text3 = token("ui-text-3")
    public static let window = token("ui-window")

    private static func token(_ name: String) -> Tone {
        guard let tone = tokens[name] else { preconditionFailure("Palette has no token named \(name)") }
        return tone
    }
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
