import Foundation

/// The panels around a bud's page: the file tree, and what the page used to carry below its
/// body. Each sits in one of the two sidebars and folds from its header.
public enum PagePanel: String, CaseIterable, Codable, Sendable {
    case files, properties, inside, whereItLives, linkedFrom, source

    /// The header's title, drawn as an eyebrow.
    public var title: String {
        switch self {
        case .files: return "Files"
        case .properties: return "Properties"
        case .inside: return "Inside"
        case .whereItLives: return "Where it lives"
        case .linkedFrom: return "Linked from"
        case .source: return "Source"
        }
    }

    /// Source starts folded: the raw file is there when wanted, not in the way.
    public var startsCollapsed: Bool { self == .source }
}

/// The two sidebars.
public enum PanelSide: String, CaseIterable, Codable, Sendable {
    case left, right
}

/// Which panels each sidebar holds, top to bottom. The default is Files alone on the left and
/// the page's own panels on the right; moving them is for later.
public struct PanelLayout: Equatable, Codable, Sendable {
    public var left: [PagePanel]
    public var right: [PagePanel]

    public init(left: [PagePanel], right: [PagePanel]) {
        self.left = left
        self.right = right
    }

    public static let standard = PanelLayout(
        left: [.files],
        right: [.properties, .inside, .whereItLives, .linkedFrom, .source]
    )

    public func panels(on side: PanelSide) -> [PagePanel] {
        side == .left ? left : right
    }

    /// Nil for a panel the layout leaves out.
    public func side(of panel: PagePanel) -> PanelSide? {
        if left.contains(panel) { return .left }
        if right.contains(panel) { return .right }
        return nil
    }
}

/// How the panels stand: which are folded and which sidebar is hidden. Kept in memory for now;
/// a saved layout comes later.
public struct PanelState: Equatable, Sendable {
    public var layout: PanelLayout
    public var collapsed: Set<PagePanel>
    public var hidden: Set<PanelSide>

    public init(layout: PanelLayout = .standard) {
        self.layout = layout
        collapsed = Set(PagePanel.allCases.filter(\.startsCollapsed))
        hidden = []
    }

    public func isCollapsed(_ panel: PagePanel) -> Bool { collapsed.contains(panel) }

    public func shows(_ side: PanelSide) -> Bool { !hidden.contains(side) }

    public mutating func toggle(_ panel: PagePanel) {
        if collapsed.contains(panel) { collapsed.remove(panel) } else { collapsed.insert(panel) }
    }

    public mutating func toggle(_ side: PanelSide) {
        if hidden.contains(side) { hidden.remove(side) } else { hidden.insert(side) }
    }
}

/// The meta on a panel row's right: what the bud holds, or its day.
public enum PanelRowText {
    public static func meta(for bud: Bud, in tree: Tree, calendar: Calendar = .current) -> String {
        let kids = tree.children(of: bud.id).count
        if kids > 0 { return "\(kids) inside" }
        if let due = bud.due { return "Due " + day(due, calendar: calendar) }
        if let when = bud.when { return day(when, calendar: calendar) }
        return ""
    }

    /// "3 Nov", the way the Today lens writes a day.
    static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.day, .month], from: date)
        let month = calendar.shortMonthSymbols[(parts.month ?? 1) - 1]
        return "\(parts.day ?? 1) \(month)"
    }
}

/// A bud's file the way the vault writes it: the front matter block, keys in the vault's order,
/// then the body. A bud with nothing set and nothing written is an empty file.
public enum MarkdownSource {
    public static func text(of bud: Bud) -> String {
        var keys: [(String, String)] = []
        if let state = bud.state { keys.append(("state", state.rawValue)) }
        if let when = bud.when { keys.append(("when", day(when))) }
        if let due = bud.due { keys.append(("due", day(due))) }
        if bud.pinned { keys.append(("pinned", "true")) }
        keys.append(("created", stamp(bud.created)))
        if let source = bud.source { keys.append(("source", scalar(source))) }
        if let from = bud.from { keys.append(("from", scalar(from))) }
        if let fromState = bud.fromState { keys.append(("from-state", scalar(fromState))) }
        if !bud.tags.isEmpty { keys.append(("tags", "[" + bud.tags.map(scalar).joined(separator: ", ") + "]")) }
        let block = keys.map { "\($0): \($1)" }.joined(separator: "\n")
        return "---\n\(block)\n---\n" + bud.body
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// `2026-11-05`.
    static func day(_ date: Date) -> String {
        let parts = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// `2026-11-05T21:00:00Z`.
    static func stamp(_ date: Date) -> String {
        let parts = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02dZ",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    /// A YAML scalar: plain when it reads back as itself, else double-quoted. A number, a
    /// boolean or null would read back as one, so they are quoted too.
    static func scalar(_ value: String) -> String {
        let plain = (value.first.map { $0.isLetter || $0.isNumber } ?? false)
            && !value.contains(": ") && !value.contains(" #") && !value.hasSuffix(" ") && !value.hasSuffix(":")
            && !value.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\t" })
            && !["true", "false", "null", "~"].contains(value.lowercased())
            && !value.allSatisfy({ $0.isNumber })
        if plain { return value }
        var out = "\""
        for character in value {
            switch character {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.append(character)
            }
        }
        return out + "\""
    }
}
