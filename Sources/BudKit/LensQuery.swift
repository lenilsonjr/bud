import Foundation

/// A question asked of the whole tree. Every facet that is set must hold for a bud to match; a
/// query with none set matches every bud. The canvas lights the hits, half-lights the path down
/// to them and fades the rest; Files lists the hits. The three lenses in Files are presets.
public struct LensQuery: Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case todo, note }
    public enum Day: Hashable, Sendable {
        /// What the Today lens shows: an open to-do due on or before the day, or a bud not done
        /// that is scheduled on or before it.
        case today
        /// An open to-do due before the day.
        case overdue
    }

    public var kind: Kind?
    public var state: BudState?
    public var day: Day?
    public var pinned: Bool
    /// The bud has an open to-do somewhere below it.
    public var holdsOpen: Bool
    /// Tags the bud must carry, every one, in its list or its body, in any case; a tag also
    /// matches the tags nested under it (`#home` matches `#home/kitchen`).
    public var tags: Set<String>
    /// Two facets that ask for different things in one slot, a to-do that is open and done:
    /// nothing answers.
    public var never = false

    public init(
        kind: Kind? = nil, state: BudState? = nil, day: Day? = nil, pinned: Bool = false, holdsOpen: Bool = false,
        tags: Set<String> = []
    ) {
        self.kind = kind
        self.state = state
        self.day = day
        self.pinned = pinned
        self.holdsOpen = holdsOpen
        self.tags = Set(tags.map(BudTags.key))
    }

    public static let todos = LensQuery(kind: .todo, state: .open)
    public static let today = LensQuery(day: .today)
    public static let pinnedBuds = LensQuery(pinned: true)

    public var isEmpty: Bool { self == LensQuery() }

    /// Both questions at once: a bud answers when it answers each. Two different answers asked
    /// of one slot (a note and a to-do, open and done) leave a question nothing answers.
    public func and(_ other: LensQuery) -> LensQuery {
        var out = self
        func merge<T: Equatable>(_ mine: T?, _ theirs: T?) -> T? {
            guard let mine, let theirs else { return mine ?? theirs }
            if mine != theirs { out.never = true }
            return mine
        }
        out.kind = merge(kind, other.kind)
        out.state = merge(state, other.state)
        out.day = merge(day, other.day)
        out.pinned = pinned || other.pinned
        out.holdsOpen = holdsOpen || other.holdsOpen
        out.tags = tags.union(other.tags)
        out.never = out.never || never || other.never
        return out
    }

    /// Whether one bud answers the question.
    public func matches(_ bud: Bud, in tree: Tree, on now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let holders = holdsOpen ? tree.holdersOfOpen() : []
        return matches(bud, holders: holders, start: calendar.startOfDay(for: now))
    }

    /// The day's start and the buds holding an open to-do are worked out once per question, not
    /// once per bud.
    private func matches(_ bud: Bud, holders: Set<UUID>, start: Date) -> Bool {
        if never { return false }
        if let kind, (kind == .todo) != bud.isTodo { return false }
        if let state, bud.state != state { return false }
        if pinned && !bud.pinned { return false }
        if let day {
            switch day {
            case .today:
                let end = start.addingTimeInterval(86_400)
                let due = bud.state == .open && (bud.due.map { $0 < end } ?? false)
                let scheduled = !bud.isDone && (bud.when.map { $0 < end } ?? false)
                if !due && !scheduled { return false }
            case .overdue:
                if !(bud.state == .open && (bud.due.map { $0 < start } ?? false)) { return false }
            }
        }
        if holdsOpen && !holders.contains(bud.id) { return false }
        if !tags.isEmpty {
            let carried = bud.allTags.map(BudTags.key)
            for tag in tags where !carried.contains(where: { $0 == tag || $0.hasPrefix(tag + "/") }) { return false }
        }
        return true
    }

    /// How a bud stands under the query.
    public enum Match: Hashable, Sendable {
        case hit
        /// Not a hit itself, but a hit sits somewhere below it.
        case path
    }

    /// Every bud under the root that is a hit or on the path to one; a bud left out is a miss.
    /// The root, an ancestor of every bud, is on the path whenever anything hits.
    public func light(_ tree: Tree, on now: Date = Date(), calendar: Calendar = .current) -> [UUID: Match] {
        var out: [UUID: Match] = [:]
        let hits = hits(tree, on: now, calendar: calendar)
        for bud in hits { out[bud.id] = .hit }
        // Climb from each hit until a bud already lit: everything above it is lit already.
        for bud in hits {
            var cursor = tree.parent(of: bud.id)
            while let above = cursor, out[above] != .path {
                if out[above] == nil { out[above] = .path }
                cursor = tree.parent(of: above)
            }
        }
        return out
    }

    /// The hits in reading order.
    public func hits(_ tree: Tree, on now: Date = Date(), calendar: Calendar = .current) -> [Bud] {
        let holders = holdsOpen ? tree.holdersOfOpen() : []
        let start = calendar.startOfDay(for: now)
        return tree.walk(under: rootID).filter { matches($0, holders: holders, start: start) }
    }
}

extension Tree {
    /// Every bud with an open to-do somewhere below it, found in one climb from each open to-do.
    func holdersOfOpen() -> Set<UUID> {
        var out: Set<UUID> = []
        for bud in walk(under: rootID) where bud.state == .open {
            for above in ancestors(of: bud.id) {
                if !out.insert(above).inserted { break }
            }
        }
        return out
    }
}

#if canImport(SwiftUI)
extension Lens {
    /// The question each Files lens asks.
    public var query: LensQuery {
        switch self {
        case .today: return .today
        case .todos: return .todos
        case .pinned: return .pinnedBuds
        }
    }
}
#endif
