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

/// The `ui-` colour tokens from the Foundations board, one per appearance.
/// `Theme` turns these into dynamic `Color`s; keep every value here so the two files never drift.
public enum Palette {
    public static let amethyst = Tone("#5B2A9E", "#C3B2EE")
    public static let amethystSoft = Tone("#5B2A9E14", "#B9A6E61F")
    public static let brand = Tone("#5B2A9E", "#5B2A9E")
    public static let canvas = Tone("#EDF3E7", "#0F1912")
    public static let card = Tone("#CDE3C1", "#21392A")
    public static let cardAgent = Tone("#E3D9F6", "#2B2445")
    public static let cardAgentInk = Tone("#3E1C70", "#DCCFF7")
    public static let cardAgentLine = Tone("#BDABE7", "#5F4D96")
    public static let cardInk = Tone("#14281B", "#EEF5EA")
    public static let cardLine = Tone("#8FB882", "#46694F")
    public static let cardLit = Tone("#8CCC8C", "#8CCC8C")
    public static let cardLitInk = Tone("#0E1C13", "#0E1C13")
    public static let cardLitLine = Tone("#4E8A55", "#C2E6BD")
    public static let cardLitMeta = Tone("#24432B", "#24432B")
    public static let cardMeta = Tone("#4B6650", "#A7BFA3")
    public static let cardNote = Tone("#E3E8C0", "#2C311F")
    public static let cardNoteLine = Tone("#B4BF79", "#5A6439")
    public static let cardNoteMeta = Tone("#626A3C", "#BBC195")
    public static let glass = Tone("#FFFFFFE0", "#18271EE0")
    public static let glow = Tone("#8CCC8C59", "#8CCC8C33")
    public static let hub = Tone("#24432B", "#24432B")
    public static let hubAccent = Tone("#8CCC8C", "#8CCC8C")
    public static let hubInk = Tone("#EEF6EA", "#EEF6EA")
    public static let hubLine = Tone("#24432B", "#4E8A55")
    public static let hubMark = Tone("#B9A6E6", "#B9A6E6")
    public static let hubMeta = Tone("#A9C7A3", "#A9C7A3")
    public static let kraft = Tone("#F6EFDF", "#1E1B13")
    public static let kraftInk = Tone("#86652A", "#D9B877")
    public static let leaf = Tone("#3B7A45", "#8CCC8C")
    public static let leafFill = Tone("#3F7F48", "#8CCC8C")
    public static let leafGlow = Tone("#8CCC8C40", "#8CCC8C1F")
    public static let leafLine = Tone("#4E8A5580", "#8CCC8C80")
    public static let leafSoft = Tone("#4E8A551C", "#8CCC8C1F")
    public static let light = Tone("#FFFFFFB3", "#8CCC8C21")
    public static let light0 = Tone("#FFFFFF00", "#8CCC8C00")
    public static let line = Tone("#1B3A2417", "#E2ECDF1A")
    public static let lineStrong = Tone("#1B3A2430", "#E2ECDF33")
    public static let lit = Tone("#DCEED3", "#22382A")
    public static let onLeaf = Tone("#FFFFFF", "#0E1C13")
    public static let pistil = Tone("#94621C", "#E3B86E")
    public static let pistilSoft = Tone("#DCAC6240", "#DCAC6226")
    public static let raised = Tone("#FFFFFF", "#1C2C22")
    public static let rose = Tone("#A23A59", "#EC9BB4")
    public static let roseSoft = Tone("#DF96B53D", "#E58AA626")
    public static let scrim = Tone("#1B2E2138", "#040A06A6")
    public static let shadow = Tone("#1B2E211A", "#00000066")
    public static let shadowStrong = Tone("#1B2E2133", "#000000A6")
    public static let sidebar = Tone("#E8EFE2", "#111C15")
    public static let surface = Tone("#FFFFFF", "#17241B")
    public static let text = Tone("#14281B", "#EEF5EA")
    public static let text2 = Tone("#435848", "#B3C4AF")
    public static let text3 = Tone("#6C7F6E", "#7E917B")
    public static let window = Tone("#F7F9F3", "#0C140F")
}

/// Corner radii: controls and checkboxes, cards and fields, bars and panels, sheets and the hub.
public enum Radius {
    public static let sm: CGFloat = 6
    public static let md: CGFloat = 10
    public static let lg: CGFloat = 14
    public static let xl: CGFloat = 22
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
