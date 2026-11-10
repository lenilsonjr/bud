import Foundation

/// The page's panels on a phone: stacked under the words rather than beside them, every one
/// folded until its header is tapped. Which are folded is this device's alone, kept in memory
/// apart from the wide layout's, since a phone and a desk want different things open. Where the
/// panels stand is still the wide layout's `PanelLayout`.
public struct PhonePanelState: Equatable, Sendable {
    public var collapsed: Set<PagePanel>

    public init() {
        collapsed = Set(PagePanel.allCases)
    }

    public func isCollapsed(_ panel: PagePanel) -> Bool { collapsed.contains(panel) }

    public mutating func toggle(_ panel: PagePanel) {
        if collapsed.contains(panel) { collapsed.remove(panel) } else { collapsed.insert(panel) }
    }

    /// The panels in the order they stack under the words: the left sidebar's then the right's.
    /// Files is left out, since the navigator above the page is the file tree on a phone.
    public static func stack(of layout: PanelLayout) -> [PagePanel] {
        (layout.left + layout.right).filter { $0 != .files }
    }
}
