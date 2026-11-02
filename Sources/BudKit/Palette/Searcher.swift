import Foundation

/// One hit in Go anywhere: a bud, its title and the trail above it.
public struct SearchHit: Hashable, Sendable {
    public let id: UUID
    public let title: String
    /// The titles above the bud, root first: "Everything › Launch the newsletter".
    public let trail: [String]

    public init(id: UUID, title: String, trail: [String]) {
        self.id = id
        self.title = title
        self.trail = trail
    }

    public var trailText: String { trail.joined(separator: " › ") }
}

/// What the palette searches. The in-memory tree today, the core's search when the vault lands.
public protocol Searcher {
    func search(_ query: String, limit: Int) -> [SearchHit]
}

/// A case-insensitive substring search over the tree: title hits first, in reading order; an
/// empty query lists nothing (the places and lenses stand in for it).
public struct TreeSearcher: Searcher {
    public let tree: Tree

    public init(tree: Tree) { self.tree = tree }

    public func search(_ query: String, limit: Int = 30) -> [SearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for bud in tree.walk(under: rootID) where bud.text.lowercased().contains(needle) {
            let trail = tree.ancestors(of: bud.id).reversed().map { tree.title(of: $0) }
            hits.append(SearchHit(id: bud.id, title: bud.text, trail: trail))
            if hits.count == limit { break }
        }
        return hits
    }
}

/// The places and lenses the palette lists beside the buds.
public enum Destination: String, CaseIterable, Sendable {
    case inbox = "Inbox", everything = "Everything", archive = "Archive"
    case today = "Today", todos = "To-dos", pinned = "Pinned"

    public var isPlace: Bool { self == .inbox || self == .everything || self == .archive }

    /// The ones that match the query by name; all of them when the query is empty.
    public static func matching(_ query: String) -> [Destination] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allCases.filter { needle.isEmpty || $0.rawValue.lowercased().contains(needle) }
    }
}
