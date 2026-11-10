import Foundation

/// Whether Files shows each of its sidebars beside the page. On a device that follows the
/// window, a sidebar shows when the window is wider than it is tall and wide enough to hold the
/// panes, and folds otherwise; elsewhere there is always room. The page bar's toggles and the
/// bar button override that, one side at a time, until the window turns the other way.
public struct SidebarVisibility: Equatable, Sendable {
    /// The narrowest window that still has room for a sidebar and a readable page.
    public static let minimumWidth: CGFloat = 700

    private let followsWindow: Bool
    private var override: [PanelSide: Bool] = [:]
    private var landscape: Bool? = nil

    /// `followsWindow` is iOS: the Mac keeps both sidebars until a toggle hides one.
    public init(followsWindow: Bool = true) {
        self.followsWindow = followsWindow
    }

    static func automatic(in size: CGSize) -> Bool {
        size.width > size.height && size.width >= minimumWidth
    }

    public func isShown(_ side: PanelSide, in size: CGSize) -> Bool {
        override[side] ?? (!followsWindow || Self.automatic(in: size))
    }

    public mutating func toggle(_ side: PanelSide, in size: CGSize) {
        override[side] = !isShown(side, in: size)
        landscape = size.width > size.height
    }

    /// The window changed shape: turning it the other way drops the toggles' choices.
    public mutating func resized(to size: CGSize) {
        let now = size.width > size.height
        if let before = landscape, before != now { override = [:] }
        landscape = now
    }
}
