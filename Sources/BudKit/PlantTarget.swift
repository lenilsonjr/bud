import Foundation

/// Where a quick line lands: in the Inbox when the screen shows Everything, under the bud on
/// screen anywhere deeper. The same rule on every platform.
public enum PlantTarget: Equatable, Sendable {
    case inbox
    case under(UUID)

    public static func forCenter(_ id: UUID) -> PlantTarget {
        id == rootID ? .inbox : .under(id)
    }

    /// The sheet's title: "New bud in Inbox" or "New bud under <title>".
    public func title(in tree: Tree) -> String {
        switch self {
        case .inbox: return "New bud in Inbox"
        case .under(let id): return "New bud under \(tree.title(of: id))"
        }
    }
}
