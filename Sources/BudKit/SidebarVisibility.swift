import Foundation

/// Whether Files shows its sidebar beside the page. By default it follows the window: shown when
/// the window is wider than it is tall and wide enough to hold both panes, collapsed otherwise.
/// The bar button overrides that until the window turns the other way.
public struct SidebarVisibility: Equatable, Sendable {
    /// The narrowest window that still has room for the sidebar and a readable page.
    public static let minimumWidth: CGFloat = 700

    private var override: Bool? = nil
    private var landscape: Bool? = nil

    public init() {}

    static func automatic(in size: CGSize) -> Bool {
        size.width > size.height && size.width >= minimumWidth
    }

    public func isShown(in size: CGSize) -> Bool {
        override ?? Self.automatic(in: size)
    }

    public mutating func toggle(in size: CGSize) {
        override = !isShown(in: size)
        landscape = size.width > size.height
    }

    /// The window changed shape: turning it the other way drops the button's choice.
    public mutating func resized(to size: CGSize) {
        let now = size.width > size.height
        if let before = landscape, before != now { override = nil }
        landscape = now
    }
}
