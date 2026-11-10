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

/// How the panels stand: where each sits and which are folded. Whether a sidebar shows at all
/// is `SidebarVisibility`. Kept in memory for now; a saved layout comes later.
public struct PanelState: Equatable, Sendable {
    public var layout: PanelLayout
    public var collapsed: Set<PagePanel>

    public init(layout: PanelLayout = .standard) {
        self.layout = layout
        collapsed = Set(PagePanel.allCases.filter(\.startsCollapsed))
    }

    public func isCollapsed(_ panel: PagePanel) -> Bool { collapsed.contains(panel) }

    public mutating func toggle(_ panel: PagePanel) {
        if collapsed.contains(panel) { collapsed.remove(panel) } else { collapsed.insert(panel) }
    }
}

/// The meta on a panel row's right: what the bud holds, or its day.
public enum PanelRowText {
    public static func meta(for bud: Bud, in tree: Tree, calendar: Calendar = .current) -> String {
        let kids = tree.children(of: bud.id).count
        if kids > 0 { return "\(kids) inside" }
        if let due = bud.due { return "Due " + DayText.short(due, calendar: calendar) }
        if let when = bud.when { return DayText.short(when, calendar: calendar) }
        return ""
    }
}
