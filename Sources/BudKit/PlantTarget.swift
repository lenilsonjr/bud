import Foundation

/// Where a quick line lands: in the Inbox only from the Capture button and the ⌥Space panel; an add
/// on the canvas plants under the bud on screen, and on Everything at the top level, so it shows
/// in the orbit. The same rule on every platform.
public enum PlantTarget: Equatable, Sendable {
    case inbox
    case under(UUID)

    /// An add on the canvas: under the bud on screen, Everything included.
    public static func forCenter(_ id: UUID) -> PlantTarget {
        .under(id)
    }

    /// The sheet's title: "New bud in Inbox", "New bud on Everything" or "New bud under <title>".
    public func title(in tree: Tree) -> String {
        switch self {
        case .inbox: return "New bud in Inbox"
        case .under(let id) where id == rootID: return "New bud on Everything"
        case .under(let id): return "New bud under \(tree.title(of: id))"
        }
    }
}
