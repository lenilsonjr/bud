import Foundation

/// A question asked of the whole tree. Every facet that is set must hold for a bud to match; a
/// query with none set matches every bud. The canvas lights the hits, half-lights the path down
/// to them and fades the rest; Files lists the hits. The three lenses in Files are presets.
public struct LensQuery: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable { case todo, note }
    public enum Day: String, Hashable, Sendable {
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
    /// Buds the bud must be linked with, every one, by a link either way.
    public var linked: Set<UUID>
    /// Something was added somewhere below the bud in the last `grownDays` days.
    public var grown: Bool
    /// Where the bud came from: the part of its source before any ":", in any case
    /// (`mail:1234` is from `mail`).
    public var source: String?
    /// How far back "Recently grown" looks.
    public static let grownDays = 7
    /// Two facets that ask for different things in one slot, a to-do that is open and done:
    /// nothing answers.
    public var never = false

    public init(
        kind: Kind? = nil, state: BudState? = nil, day: Day? = nil, pinned: Bool = false, holdsOpen: Bool = false,
        tags: Set<String> = [], linked: Set<UUID> = [], grown: Bool = false, source: String? = nil
    ) {
        self.kind = kind
        self.state = state
        self.day = day
        self.pinned = pinned
        self.holdsOpen = holdsOpen
        self.tags = Set(tags.map(BudTags.key))
        self.linked = linked
        self.grown = grown
        self.source = source.flatMap(Self.sourceKey)
    }

    /// Where "Recently grown" starts: `grownDays` days before the start of today, so the window
    /// moves at midnight with the rest of the day's lenses, not by the minute.
    static func grownSince(_ now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -grownDays, to: today) ?? today
    }

    /// The source a bud's provenance names: what comes before any ":", lowercased; nil for none.
    public static func sourceKey(_ provenance: String?) -> String? {
        guard let provenance else { return nil }
        let key = provenance.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        guard !key.isEmpty else { return nil }
        // The Mac's capture panel says "desktop"; it is the Mac all the same.
        return key == "desktop" ? "mac" : key
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
        out.grown = grown || other.grown
        out.source = merge(source, other.source)
        out.tags = tags.union(other.tags)
        out.linked = linked.union(other.linked)
        out.never = out.never || never || other.never
        return out
    }

    /// Whether one bud answers the question.
    public func matches(_ bud: Bud, in tree: Tree, on now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let holders = holdsOpen ? tree.holdersOfOpen() : []
        let growers = grown ? tree.grown(since: Self.grownSince(now, calendar: calendar)) : []
        return matches(
            bud, holders: holders, growers: growers, around: around(in: tree, links: nil),
            start: calendar.startOfDay(for: now)
        )
    }

    /// For each bud the query asks to be linked with, the buds linked with it: the links read
    /// once per question, or handed over by a caller that holds them already.
    private func around(in tree: Tree, links: LinkGraph?) -> [Set<UUID>] {
        guard !linked.isEmpty else { return [] }
        let graph = links ?? LinkGraph(tree)
        return linked.map { Set(graph.around($0).map(\.other)) }
    }

    /// The day's start and the buds holding an open to-do are worked out once per question, not
    /// once per bud.
    private func matches(_ bud: Bud, holders: Set<UUID>, growers: Set<UUID>, around: [Set<UUID>], start: Date) -> Bool {
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
        if grown && !growers.contains(bud.id) { return false }
        if let source, Self.sourceKey(bud.source) != source { return false }
        if !tags.isEmpty {
            let carried = bud.allTags.map(BudTags.key)
            for tag in tags where !carried.contains(where: { $0 == tag || $0.hasPrefix(tag + "/") }) { return false }
        }
        for others in around where !others.contains(bud.id) { return false }
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
    /// A bud the question is linked with is on the path too, while anything hits: the answer
    /// keeps what it was asked about in view.
    public func light(
        _ tree: Tree, links: LinkGraph? = nil, on now: Date = Date(), calendar: Calendar = .current
    ) -> [UUID: Match] {
        var out: [UUID: Match] = [:]
        let hits = hits(tree, links: links, on: now, calendar: calendar)
        for bud in hits { out[bud.id] = .hit }
        // Climb from each hit until a bud already lit: everything above it is lit already.
        func climb(from id: UUID) {
            var cursor = tree.parent(of: id)
            while let above = cursor, out[above] != .path {
                if out[above] == nil { out[above] = .path }
                cursor = tree.parent(of: above)
            }
        }
        for bud in hits { climb(from: bud.id) }
        if !hits.isEmpty {
            for id in linked where tree.bud(id) != nil {
                if out[id] == nil { out[id] = .path }
                climb(from: id)
            }
        }
        return out
    }

    /// The hits in reading order.
    public func hits(
        _ tree: Tree, links: LinkGraph? = nil, on now: Date = Date(), calendar: Calendar = .current
    ) -> [Bud] {
        let holders = holdsOpen ? tree.holdersOfOpen() : []
        let start = calendar.startOfDay(for: now)
        let around = around(in: tree, links: links)
        let growers = grown ? tree.grown(since: Self.grownSince(now, calendar: calendar)) : []
        return tree.walk(under: rootID).filter {
            matches($0, holders: holders, growers: growers, around: around, start: start)
        }
    }
}

extension LensQuery {
    /// The hits grouped by the top-level thread they sit under, threads in their order and the
    /// hits in reading order: how a saved lens's page lists them. A thread that is a hit itself
    /// heads its own group. Hits come in reading order, so each thread's group starts where its
    /// first hit is; each hit climbs to its thread once, through parents read in one pass.
    public func hitsByThread(
        _ tree: Tree, links: LinkGraph? = nil, on now: Date = Date(), calendar: Calendar = .current
    ) -> [(thread: Bud, hits: [Bud])] {
        let hits = hits(tree, links: links, on: now, calendar: calendar)
        guard !hits.isEmpty else { return [] }
        let byID = Dictionary(tree.buds.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var top: [UUID: UUID] = [:]
        func thread(of id: UUID) -> UUID? {
            var path: [UUID] = []
            var cursor = id
            var found: UUID?
            while found == nil, let bud = byID[cursor] {
                if let known = top[cursor] { found = known; break }
                path.append(cursor)
                if bud.parent == rootID { found = cursor } else { cursor = bud.parent }
                if path.count > byID.count { break }
            }
            for step in path { top[step] = found }
            return found
        }
        var out: [(thread: Bud, hits: [Bud])] = []
        var at: [UUID: Int] = [:]
        for bud in hits {
            guard let id = thread(of: bud.id), let head = byID[id] else { continue }
            if let i = at[id] {
                out[i].hits.append(bud)
            } else {
                at[id] = out.count
                out.append((head, [bud]))
            }
        }
        return out
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

    /// Every bud that something was added below since `date`, at any depth.
    func grown(since date: Date) -> Set<UUID> {
        var out: Set<UUID> = []
        for bud in walk(under: rootID) where bud.created >= date {
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
