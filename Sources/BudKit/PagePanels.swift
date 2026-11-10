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

    public var other: PanelSide { self == .left ? .right : .left }

    /// "left sidebar", as the menu names it.
    public var name: String { "\(rawValue) sidebar" }
}

/// Which panels each sidebar holds, top to bottom. The default is Files alone on the left and
/// the page's own panels on the right. A panel on neither side is hidden. The layout is one per
/// vault: the store keeps it in the vault's shared maps, so every device shows the same.
public struct PanelLayout: Equatable, Codable, Sendable {
    public var left: [PagePanel]
    public var right: [PagePanel]

    public init(left: [PagePanel], right: [PagePanel]) {
        self.left = left
        self.right = right
    }

    /// Reads a layout another build may have written: a panel this build does not know is
    /// skipped, the known ones keep their order, one listed twice keeps its first place, and a
    /// known panel on neither side is hidden.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var seen: Set<PagePanel> = []
        let once = { (names: [String]) -> [PagePanel] in
            names.compactMap(PagePanel.init(rawValue:)).filter { seen.insert($0).inserted }
        }
        left = try once(container.decode([String].self, forKey: .left))
        right = try once(container.decode([String].self, forKey: .right))
    }

    private enum CodingKeys: String, CodingKey {
        case left, right
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

    /// The panels neither sidebar holds, in their usual order.
    public var hidden: [PagePanel] { PagePanel.allCases.filter { side(of: $0) == nil } }

    /// Whether a page shows a panel: the page's own panels go with a bud's page alone, so a
    /// lens, a place and Everything show the file tree only.
    public static func shows(_ panel: PagePanel, onBudPage: Bool) -> Bool {
        onBudPage || panel == .files
    }

    /// The panels a side shows on the page.
    public func shown(on side: PanelSide, onBudPage: Bool) -> [PagePanel] {
        panels(on: side).filter { Self.shows($0, onBudPage: onBudPage) }
    }

    /// Puts a panel on a side at a place in that sidebar, taking it from wherever it was; a
    /// place past the end puts it last.
    public mutating func move(_ panel: PagePanel, to side: PanelSide, at index: Int) {
        remove(panel)
        var panels = self.panels(on: side)
        panels.insert(panel, at: max(0, min(index, panels.count)))
        set(panels, on: side)
    }

    /// Trades places with the panel above; nothing at the top.
    public mutating func moveUp(_ panel: PagePanel) {
        guard let side = side(of: panel), let i = panels(on: side).firstIndex(of: panel), i > 0 else { return }
        var panels = self.panels(on: side)
        panels.swapAt(i, i - 1)
        set(panels, on: side)
    }

    /// Trades places with the panel below; nothing at the bottom.
    public mutating func moveDown(_ panel: PagePanel) {
        guard let side = side(of: panel), let i = panels(on: side).firstIndex(of: panel), i < panels(on: side).count - 1 else { return }
        var panels = self.panels(on: side)
        panels.swapAt(i, i + 1)
        set(panels, on: side)
    }

    public func canMoveUp(_ panel: PagePanel) -> Bool {
        guard let side = side(of: panel) else { return false }
        return panels(on: side).first != panel
    }

    public func canMoveDown(_ panel: PagePanel) -> Bool {
        guard let side = side(of: panel) else { return false }
        return panels(on: side).last != panel
    }

    /// Takes a panel out of its sidebar; Show hidden panels brings it back.
    public mutating func hide(_ panel: PagePanel) { remove(panel) }

    /// Puts every hidden panel back, each at the end of the side it usually has.
    public mutating func showHidden() {
        for panel in hidden {
            move(panel, to: Self.standard.side(of: panel) ?? .right, at: .max)
        }
    }

    private mutating func remove(_ panel: PagePanel) {
        left.removeAll { $0 == panel }
        right.removeAll { $0 == panel }
    }

    private mutating func set(_ panels: [PagePanel], on side: PanelSide) {
        if side == .left { left = panels } else { right = panels }
    }
}

extension PanelLayout {
    /// The panels in the order they stack under the words on a phone: the left sidebar's then
    /// the right's. Files is left out, since the navigator above the page is the file tree there.
    public var phoneStack: [PagePanel] { (left + right).filter { $0 != .files } }
}

/// Which panels are folded from their headers. A sidebar starts with Source alone folded; the
/// stack under the words on a phone starts with every panel folded.
public struct PanelFolds: Equatable, Sendable {
    public var collapsed: Set<PagePanel>

    public init(collapsed: Set<PagePanel>) {
        self.collapsed = collapsed
    }

    public static let sidebar = PanelFolds(collapsed: Set(PagePanel.allCases.filter(\.startsCollapsed)))
    public static let phone = PanelFolds(collapsed: Set(PagePanel.allCases))

    public func isCollapsed(_ panel: PagePanel) -> Bool { collapsed.contains(panel) }

    public mutating func toggle(_ panel: PagePanel) {
        if collapsed.contains(panel) { collapsed.remove(panel) } else { collapsed.insert(panel) }
    }
}

/// How the panels stand: where each sits and which are folded. Whether a sidebar shows at all
/// is `SidebarVisibility`. The layout is the vault's; folding stays on this device, in memory,
/// and a phone folds apart from the sidebars, since a desk and a phone want different things
/// open. `compact` names the phone, where the panels stack under the words.
public struct PanelState: Equatable, Sendable {
    public var layout: PanelLayout
    public var folds = PanelFolds.sidebar
    public var phoneFolds = PanelFolds.phone

    public init(layout: PanelLayout = .standard) {
        self.layout = layout
    }

    public func isCollapsed(_ panel: PagePanel, compact: Bool = false) -> Bool {
        (compact ? phoneFolds : folds).isCollapsed(panel)
    }

    public mutating func toggle(_ panel: PagePanel, compact: Bool = false) {
        if compact { phoneFolds.toggle(panel) } else { folds.toggle(panel) }
    }

    /// Unfolds a panel so what is added to it can be seen; nothing when it is open.
    public mutating func show(_ panel: PagePanel, compact: Bool = false) {
        if isCollapsed(panel, compact: compact) { toggle(panel, compact: compact) }
    }
}

/// A gap between a sidebar's panels, where a dragged panel lands: before the `gap`th panel of
/// the side, or after the last one when `gap` is their count.
public struct PanelDrop: Equatable, Sendable {
    public var side: PanelSide
    public var gap: Int

    public init(side: PanelSide, gap: Int) {
        self.side = side
        self.gap = gap
    }

    /// Which edge of a panel the drop line is drawn on: the top of the panel at the gap, or the
    /// bottom of the last one.
    public enum Line: Sendable { case above, below }

    public func line(on panel: PagePanel, in layout: PanelLayout) -> Line? {
        let panels = layout.panels(on: side)
        if gap < panels.count { return panels[gap] == panel ? .above : nil }
        return panels.last == panel ? .below : nil
    }

    /// The place the moved panel takes on the side, since the gaps count its old place too.
    public func index(moving panel: PagePanel, in layout: PanelLayout) -> Int {
        if layout.side(of: panel) == side, let i = layout.panels(on: side).firstIndex(of: panel), i < gap {
            return gap - 1
        }
        return gap
    }

    /// Which sidebar a point is over, from the width of each one shown; nil over the page.
    public static func side(at x: CGFloat, in width: CGFloat, left: CGFloat?, right: CGFloat?) -> PanelSide? {
        if let left, x < left { return .left }
        if let right, x > width - right { return .right }
        return nil
    }

    /// The gap under a point on a side: after every panel whose middle is above it, from the
    /// panels' frames in the same space as the point.
    public static func under(_ point: CGPoint, on side: PanelSide, frames: [PagePanel: CGRect], layout: PanelLayout) -> PanelDrop {
        var gap = 0
        for (i, panel) in layout.panels(on: side).enumerated() {
            if let frame = frames[panel], frame.midY <= point.y { gap = i + 1 }
        }
        return PanelDrop(side: side, gap: gap)
    }
}

/// A panel in hand: which, where the pointer is, and the gap it would land in.
public struct PanelDrag: Equatable, Sendable {
    public var panel: PagePanel
    public var point: CGPoint
    public var drop: PanelDrop?

    public init(panel: PagePanel, point: CGPoint, drop: PanelDrop? = nil) {
        self.panel = panel
        self.point = point
        self.drop = drop
    }

    /// Where the drop line is drawn on a panel; none for a gap beside the panel in hand, where
    /// a drop changes nothing.
    public func line(on target: PagePanel, in layout: PanelLayout) -> PanelDrop.Line? {
        guard let drop else { return nil }
        if layout.side(of: panel) == drop.side, let i = layout.panels(on: drop.side).firstIndex(of: panel),
           drop.gap == i || drop.gap == i + 1 {
            return nil
        }
        return drop.line(on: target, in: layout)
    }
}

/// The ⋯ menu on a panel's header, top to bottom, in three groups: moving it, folding or hiding
/// it, and the layout as a whole. The words are here so a test reads them on any platform.
public enum PanelMenuItem: CaseIterable, Sendable {
    case moveToOtherSide, moveUp, moveDown, collapse, hide, showHidden, reset

    /// The first item of a group after the first.
    public var startsGroup: Bool { self == .collapse || self == .showHidden }

    public func title(for panel: PagePanel, in state: PanelState) -> String {
        switch self {
        case .moveToOtherSide: return "Move to \((state.layout.side(of: panel) ?? .right).other.name)"
        case .moveUp: return "Move up"
        case .moveDown: return "Move down"
        case .collapse: return state.isCollapsed(panel) ? "Expand" : "Collapse"
        case .hide: return "Hide panel"
        case .showHidden: return "Show hidden panels"
        case .reset: return "Reset layout"
        }
    }

    /// Whether it does anything from here: the last panel the page shows cannot hide, since the
    /// menu to show the others would go with it.
    public func isEnabled(for panel: PagePanel, in state: PanelState, onBudPage: Bool = true) -> Bool {
        switch self {
        case .moveToOtherSide, .collapse: return true
        case .moveUp: return state.layout.canMoveUp(panel)
        case .moveDown: return state.layout.canMoveDown(panel)
        case .hide:
            return PanelSide.allCases.reduce(0) { $0 + state.layout.shown(on: $1, onBudPage: onBudPage).count } > 1
        case .showHidden: return !state.layout.hidden.isEmpty
        case .reset: return state.layout != .standard
        }
    }

    public func apply(to state: inout PanelState, for panel: PagePanel) {
        switch self {
        case .moveToOtherSide: state.layout.move(panel, to: (state.layout.side(of: panel) ?? .right).other, at: .max)
        case .moveUp: state.layout.moveUp(panel)
        case .moveDown: state.layout.moveDown(panel)
        case .collapse: state.toggle(panel)
        case .hide: state.layout.hide(panel)
        case .showHidden: state.layout.showHidden()
        case .reset: state.layout = .standard
        }
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
