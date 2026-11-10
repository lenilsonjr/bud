import Foundation

/// One row of the canvas lens menu. Ticked rows combine: a bud must answer every one.
public enum LensFacet: Hashable, Sendable {
    case openTodos, dueToday, recentlyGrown, pinned, done
    /// A tag, by the way the menu shows it; two spellings of one tag are the same row.
    case tag(String)
    /// Buds from one source, by its key (`mail`, `mac`).
    case source(String)
    /// The buds linked with one bud, either way; the title is the bud's when it was picked.
    case linked(UUID, title: String)
    /// A saved lens, asked exactly as it was saved; the name is the one it had when ticked.
    case saved(SavedLens)

    public static func == (a: LensFacet, b: LensFacet) -> Bool { a.identity == b.identity }
    public func hash(into hasher: inout Hasher) { hasher.combine(identity) }

    private var identity: String {
        switch self {
        case .tag(let tag): return "#" + BudTags.key(tag)
        case .linked(let id, _): return "@" + id.uuidString
        case .source(let key): return "from:" + key
        case .saved(let lens): return "saved:" + lens.id.uuidString
        default: return name
        }
    }

    /// The built-in rows, in the menu's order.
    public static let builtIns: [LensFacet] = [.openTodos, .dueToday, .recentlyGrown, .pinned, .done]

    public var name: String {
        switch self {
        case .openTodos: return "Open to-dos"
        case .dueToday: return "Due today"
        case .recentlyGrown: return "Recently grown"
        case .source(let key): return "From \(Self.sourceName(key))"
        case .pinned: return "Pinned"
        case .done: return "Done"
        case .tag(let tag): return "#\(tag)"
        case .linked(_, let title): return "Linked to \(title)"
        case .saved(let lens): return lens.name
        }
    }

    public var systemImage: String {
        switch self {
        case .openTodos: return "circle"
        case .dueToday: return "flag"
        case .recentlyGrown: return "leaf"
        case .source: return "tray.and.arrow.down"
        case .pinned: return "pin"
        case .done: return "checkmark.circle"
        case .tag: return "number"
        case .linked: return "link"
        case .saved: return "line.3.horizontal.decrease.circle"
        }
    }

    /// The question this row asks alone.
    public var query: LensQuery {
        switch self {
        case .openTodos: return .todos
        case .dueToday: return .today
        case .recentlyGrown: return LensQuery(grown: true)
        case .source(let key): return LensQuery(source: key)
        case .pinned: return .pinnedBuds
        case .done: return LensQuery(state: .done)
        case .tag(let tag): return LensQuery(tags: [tag])
        case .linked(let id, _): return LensQuery(linked: [id])
        case .saved(let lens): return lens.query
        }
    }

    /// A source as people write it: the names Bud knows, otherwise the key with a capital.
    static func sourceName(_ key: String) -> String {
        let known = [
            "mac": "Mac", "iphone": "iPhone", "ipad": "iPad", "tv": "TV",
        ]
        return known[key] ?? key.prefix(1).uppercased() + key.dropFirst()
    }

    /// The question ticked rows ask together; nil when none is ticked.
    public static func query(of facets: some Sequence<LensFacet>) -> LensQuery? {
        facets.reduce(nil as LensQuery?) { sum, facet in sum.map { $0.and(facet.query) } ?? facet.query }
    }
}
