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

/// A case-insensitive substring search over the tree: title hits first, in reading order. An
/// empty query lists the most recently created buds, newest first, so the palette opens on
/// where you were last working.
public struct TreeSearcher: Searcher {
    public let tree: Tree

    /// How many recent buds an empty query lists.
    public static let recentCount = 8

    public init(tree: Tree) { self.tree = tree }

    public func search(_ query: String, limit: Int = 30) -> [SearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = tree.walk(under: rootID) + tree.walk(under: inboxID)
        if needle.isEmpty {
            return all.sorted { $0.created > $1.created }.prefix(Self.recentCount).map(hit)
        }
        var hits: [SearchHit] = []
        for bud in all where bud.text.lowercased().contains(needle) {
            hits.append(hit(bud))
            if hits.count == limit { break }
        }
        return hits
    }

    private func hit(_ bud: Bud) -> SearchHit {
        SearchHit(id: bud.id, title: bud.text, trail: tree.ancestors(of: bud.id).reversed().map { tree.title(of: $0) })
    }
}

/// The homes a bud can be moved to: Everything and every bud under it, except the bud itself and
/// its own branch. An empty query lists them all; otherwise a case-insensitive substring of the
/// title. The inbox is not a home.
public struct MoveTargets {
    public let tree: Tree

    public init(tree: Tree) { self.tree = tree }

    public func matching(_ query: String, for id: UUID) -> [SearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let excluded = Set(tree.descendants(of: id) + [id])
        let everything = SearchHit(id: rootID, title: tree.title(of: rootID), trail: [])
        let buds = tree.walk(under: rootID).filter { !excluded.contains($0.id) }.map { bud in
            SearchHit(id: bud.id, title: bud.text, trail: tree.ancestors(of: bud.id).reversed().map { tree.title(of: $0) })
        }
        return ([everything] + buds).filter { needle.isEmpty || $0.title.lowercased().contains(needle) }
    }
}

/// The places and lenses the palette lists beside the buds.
public enum Destination: String, CaseIterable, Sendable {
    case inbox = "Inbox", everything = "Everything", archive = "Archive", trash = "Trash"
    case today = "Today", todos = "To-dos", pinned = "Pinned"

    public var isPlace: Bool { self == .inbox || self == .everything || self == .archive || self == .trash }

    /// The ones that match the query by name; all of them when the query is empty.
    public static func matching(_ query: String) -> [Destination] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allCases.filter { needle.isEmpty || $0.rawValue.lowercased().contains(needle) }
    }
}
