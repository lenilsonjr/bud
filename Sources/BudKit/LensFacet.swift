import Foundation

/// One row of the canvas lens menu. Ticked rows combine: a bud must answer every one.
public enum LensFacet: Hashable, Sendable {
    case openTodos, dueToday, pinned, done
    /// A tag, by the way the menu shows it.
    case tag(String)

    /// The built-in rows, in the menu's order.
    public static let builtIns: [LensFacet] = [.openTodos, .dueToday, .pinned, .done]

    public var name: String {
        switch self {
        case .openTodos: return "Open to-dos"
        case .dueToday: return "Due today"
        case .pinned: return "Pinned"
        case .done: return "Done"
        case .tag(let tag): return "#\(tag)"
        }
    }

    public var systemImage: String {
        switch self {
        case .openTodos: return "square"
        case .dueToday: return "flag"
        case .pinned: return "pin"
        case .done: return "checkmark.square"
        case .tag: return "number"
        }
    }

    /// The question this row asks alone.
    public var query: LensQuery {
        switch self {
        case .openTodos: return .todos
        case .dueToday: return .today
        case .pinned: return .pinnedBuds
        case .done: return LensQuery(state: .done)
        case .tag(let tag): return LensQuery(tags: [tag])
        }
    }

    /// The question ticked rows ask together; nil when none is ticked.
    public static func query(of facets: some Sequence<LensFacet>) -> LensQuery? {
        facets.reduce(nil as LensQuery?) { sum, facet in sum.map { $0.and(facet.query) } ?? facet.query }
    }
}
