import Foundation

/// The board of a bud: everything inside it, each bud a card, in columns. Open comes first, then
/// one column per tag in the person's order, then Done, then Cancelled. The columns are what the
/// page draws; which tags have a column is `BoardColumns`, kept per bud in the vault.
public struct Board: Equatable, Sendable {
    /// The bud whose board it is, by title.
    public var title: String
    /// How many buds are inside, at any depth: "Everything inside · 17".
    public var inside: Int
    /// Open, the tag columns, Done: the ones laid side by side.
    public var columns: [BoardColumn]
    /// The last column, folded until "Show cancelled".
    public var cancelled: BoardColumn

    /// "Everything inside · 17", the line beside the title.
    public var scope: String { "Everything inside · \(inside)" }

    /// The board of `center` in `tree`: its descendants in reading order, each under the first
    /// column that takes it. A done bud goes to Done and a cancelled one to Cancelled whatever
    /// tags it carries; a bud with a column's tag goes to the first such column in `tags`, with
    /// its other tags on the card; every other bud, notes included, is Open. `tags` nil takes
    /// the default: every tag the buds inside carry, in the order they are first met.
    public init(tree: Tree, center: UUID, tags: [String]? = nil) {
        let buds = tree.walk(under: center)
        title = tree.title(of: center)
        inside = buds.count
        // One pass over the walk for what each card needs of the tree: the walk reads a parent
        // before its children, so read backwards each bud's count is complete before its
        // parent adds it, and the titles are at hand for the trails.
        var titles: [UUID: String] = [center: title]
        var parents: [UUID: UUID] = [:]
        var sizes: [UUID: Int] = [:]
        for bud in buds {
            titles[bud.id] = bud.text
            parents[bud.id] = bud.parent
        }
        for bud in buds.reversed() {
            sizes[bud.parent, default: 0] += 1 + sizes[bud.id, default: 0]
        }
        let order = tags ?? BoardColumns.inUse(by: buds)
        var open: [BoardCard] = [], done: [BoardCard] = [], gone: [BoardCard] = []
        var tagged: [[BoardCard]] = Array(repeating: [], count: order.count)
        let keys = order.map(BudTags.key)
        for bud in buds {
            var trail: [String] = []
            var cursor: UUID? = bud.parent
            while let id = cursor, id != center, let title = titles[id] {
                trail.append(title)
                cursor = parents[id]
            }
            trail.append(title)
            var card = BoardCard(
                id: bud.id, title: bud.text, trail: trail.reversed(), isTodo: bud.isTodo, isDone: bud.isDone,
                isCancelled: bud.isCancelled, when: bud.when, due: bud.due, tags: bud.allTags, inside: sizes[bud.id] ?? 0
            )
            if bud.isCancelled { gone.append(card); continue }
            if bud.isDone { done.append(card); continue }
            if let column = keys.firstIndex(where: { key in card.tags.contains { BudTags.key($0) == key } }) {
                card.tags.removeAll { BudTags.key($0) == keys[column] }
                tagged[column].append(card)
            } else {
                open.append(card)
            }
        }
        columns = [BoardColumn(kind: .open, cards: open)]
            + zip(order, tagged).map { BoardColumn(kind: .tag($0), cards: $1) }
            + [BoardColumn(kind: .done, cards: done)]
        cancelled = BoardColumn(kind: .cancelled, cards: gone)
    }
}

/// One column of a board.
public struct BoardColumn: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Hashable, Sendable {
        case open, tag(String), done, cancelled
    }

    public var kind: Kind
    public var cards: [BoardCard]

    public init(kind: Kind, cards: [BoardCard]) {
        self.kind = kind
        self.cards = cards
    }

    public var id: Kind { kind }

    /// The header's word: "OPEN", "DONE" and "CANCELLED" are eyebrows, a tag column reads its
    /// tag as a chip.
    public var title: String {
        switch kind {
        case .open: return "Open"
        case .tag(let tag): return "#\(tag)"
        case .done: return "Done"
        case .cancelled: return "Cancelled"
        }
    }

    public var tag: String? {
        if case .tag(let tag) = kind { return tag }
        return nil
    }

    /// Open, Done and Cancelled sit on the sidebar tone; a tag column is a line around nothing.
    public var isFixed: Bool { tag == nil }
}

/// One bud as its card shows it. The card is read-only this round: the fields are what the
/// board draws, nothing it changes. Its picture is not here: the vault's index knows which
/// picture a bud embeds first, and the page asks the store for it by the card's id.
public struct BoardCard: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    /// The titles from the board's bud down to the card's parent: "Moving to Lisbon" for a bud
    /// right inside, "Moving to Lisbon › Learn Portuguese" one deeper.
    public var trail: [String]
    public var isTodo: Bool
    public var isDone: Bool
    public var isCancelled: Bool
    public var when: Date?
    public var due: Date?
    /// The tags the card shows: every tag the bud carries but the one its column is for.
    public var tags: [String]
    /// How many buds are inside it, at any depth.
    public var inside: Int

    public init(
        id: UUID, title: String, trail: [String] = [], isTodo: Bool = false, isDone: Bool = false,
        isCancelled: Bool = false, when: Date? = nil, due: Date? = nil, tags: [String] = [], inside: Int = 0
    ) {
        self.id = id
        self.title = title
        self.trail = trail
        self.isTodo = isTodo
        self.isDone = isDone
        self.isCancelled = isCancelled
        self.when = when
        self.due = due
        self.tags = tags
        self.inside = inside
    }

    /// "Moving to Lisbon › Learn Portuguese".
    public var trailText: String { trail.joined(separator: " › ") }

    /// "6 inside"; nil for a leaf.
    public var insideText: String? { inside > 0 ? "\(inside) inside" : nil }

    /// "Today", "Sat", "3 Nov": the when tag's word.
    public func whenText(now: Date, calendar: Calendar = .current) -> String? {
        when.map { DayText.relative($0, now: now, calendar: calendar) }
    }

    /// "Due Fri", "Due 30 Nov": the due tag's word.
    public func dueText(now: Date, calendar: Calendar = .current) -> String? {
        due.map { "Due " + DayText.relative($0, now: now, calendar: calendar) }
    }
}

/// Which tags have a column on a bud's board, in the person's order. One list per bud, in the
/// vault's `board` map under the bud's id, so every device shows the same columns.
public struct BoardColumns: Equatable, Codable, Sendable {
    /// Each a tag as written, once: a spelling that is not a tag is dropped, and one listed
    /// twice keeps its first place.
    public private(set) var tags: [String]

    public init(tags: [String]) {
        var seen: Set<String> = []
        self.tags = tags.compactMap(BudTags.clean).filter { seen.insert(BudTags.key($0)).inserted }
    }

    /// The default when nothing is stored: every tag the buds carry, each once, in the order
    /// they are first met reading down the board.
    public static func inUse(by buds: [Bud]) -> [String] {
        var seen: Set<String> = []
        return buds.flatMap(\.allTags).filter { seen.insert(BudTags.key($0)).inserted }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(tags: try container.decode([String].self, forKey: .tags))
    }

    private enum CodingKeys: String, CodingKey {
        case tags
    }
}

extension Bud {
    /// A planted bud whose source item was cancelled: its `from-state`. Nothing else cancels a
    /// bud yet.
    public var isCancelled: Bool { fromState == "cancelled" }
}

extension DayText {
    /// A day relative to now, as a card's tag reads it: "Today", "Tomorrow", "Yesterday", the
    /// weekday for the rest of the coming week ("Sat"), and the short date beyond ("3 Nov").
    public static func relative(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...6: return formatter(template: "EEE", calendar: calendar).string(from: day)
        default: return short(day, calendar: calendar)
        }
    }
}
