import Foundation

// MARK: adding, moving and taking away columns

extension BoardColumns {
    /// Whether `tag`, in any case, has a column.
    public func has(_ tag: String) -> Bool {
        tags.contains { BudTags.key($0) == BudTags.key(tag) }
    }

    /// Adds a column for `tag` at the end, after the last tag column; nothing for a spelling
    /// that is not a tag or one that has a column already.
    public mutating func add(_ tag: String) {
        guard let tag = BudTags.clean(tag), !has(tag) else { return }
        self = BoardColumns(tags: tags + [tag])
    }

    /// Takes the column of `tag` away. The buds keep the tag: the board alone forgets it.
    public mutating func remove(_ tag: String) {
        self = BoardColumns(tags: tags.filter { BudTags.key($0) != BudTags.key(tag) })
    }

    /// Moves the column of `tag` to `index` among the tag columns, taking it from where it was;
    /// a place past the end puts it last. Nothing for a tag without a column.
    public mutating func move(_ tag: String, to index: Int) {
        guard let i = tags.firstIndex(where: { BudTags.key($0) == BudTags.key(tag) }) else { return }
        var moved = tags
        let column = moved.remove(at: i)
        moved.insert(column, at: max(0, min(index, moved.count)))
        self = BoardColumns(tags: moved)
    }

    /// Trades places with the column before; nothing at the start.
    public mutating func moveLeft(_ tag: String) {
        guard let i = tags.firstIndex(where: { BudTags.key($0) == BudTags.key(tag) }), i > 0 else { return }
        move(tag, to: i - 1)
    }

    /// Trades places with the column after; nothing at the end.
    public mutating func moveRight(_ tag: String) {
        guard let i = tags.firstIndex(where: { BudTags.key($0) == BudTags.key(tag) }), i < tags.count - 1 else { return }
        move(tag, to: i + 1)
    }

    public func canMoveLeft(_ tag: String) -> Bool {
        has(tag) && BudTags.key(tags[0]) != BudTags.key(tag)
    }

    public func canMoveRight(_ tag: String) -> Bool {
        has(tag) && BudTags.key(tags[tags.count - 1]) != BudTags.key(tag)
    }
}

// MARK: the picker

/// What Add column offers for what is typed: the tags on this board, which are the columns'
/// tags and then the tags the buds inside carry without a column yet; the other tags in the
/// vault, most used first; and a new tag column for a spelling no bud uses, when one is typed.
/// A tag that has a column already is listed with a check and cannot be picked twice.
public struct BoardTagChoices: Equatable, Sendable {
    public struct Row: Equatable, Hashable, Sendable {
        public var tag: String
        /// Whether the board shows a column for it already.
        public var hasColumn: Bool

        public init(tag: String, hasColumn: Bool = false) {
            self.tag = tag
            self.hasColumn = hasColumn
        }
    }

    /// "On this board": the columns' tags in their order, then the tags in use inside without
    /// a column, in the order they are first met.
    public var onBoard: [Row]
    /// "Other tags": every tag in the vault the board does not know, most used first.
    public var others: [Row]
    /// "New tag column #typed": the typed spelling when it is a tag no bud uses and no column
    /// has; nil otherwise, when the row reads as the hint alone.
    public var create: String?

    public init(onBoard: [Row] = [], others: [Row] = [], create: String? = nil) {
        self.onBoard = onBoard
        self.others = others
        self.create = create
    }

    /// The rows a pick can take, top to bottom: the tags without a column, then the new one.
    public var pickable: [Row] {
        (onBoard + others).filter { !$0.hasColumn }
    }

    /// How many rows a pick can land on, the new tag column counted.
    public var count: Int { pickable.count + (create == nil ? 0 : 1) }

    /// The choices for `query`, in any case: a tag whose name holds the typed text stays, the
    /// ones that start with it first in each group.
    public static func rows(for query: String, columns: BoardColumns, inside: [Bud], counts: [TagCount]) -> BoardTagChoices {
        let typed = String(query.trimmingCharacters(in: .whitespaces).drop { $0 == "#" })
        let wanted = BudTags.key(typed)
        let columnKeys = Set(columns.tags.map(BudTags.key))
        var seen = columnKeys
        let carried = BoardColumns.inUse(by: inside).filter { seen.insert(BudTags.key($0)).inserted }
        let onBoard = columns.tags.map { Row(tag: $0, hasColumn: true) } + carried.map { Row(tag: $0) }
        let others = counts.map(\.tag).filter { seen.insert(BudTags.key($0)).inserted }.map { Row(tag: $0) }
        let taken = seen.contains(wanted)
        let create = taken ? nil : BudTags.clean(typed)
        return BoardTagChoices(onBoard: matching(onBoard, wanted), others: matching(others, wanted), create: create)
    }

    private static func matching(_ rows: [Row], _ wanted: String) -> [Row] {
        guard !wanted.isEmpty else { return rows }
        let found = rows.filter { BudTags.key($0.tag).contains(wanted) }
        return found.filter { BudTags.key($0.tag).hasPrefix(wanted) } + found.filter { !BudTags.key($0.tag).hasPrefix(wanted) }
    }
}

/// The words of the picker, here so a test reads them on any platform.
public enum BoardColumnText {
    public static let find = "Find or create a tag"
    public static let onBoard = "On this board"
    public static let others = "Other tags"
    public static let newColumn = "New tag column"
    public static let add = "Add column"
    /// "New tag column #blocked": the create row once a new tag is typed.
    public static func create(_ tag: String) -> String { "\(newColumn) #\(tag)" }
}

// MARK: the header menu

/// The ⋯ menu on a tag column's header, top to bottom: moving it, then taking it off the
/// board. Each edits the board's columns alone; no bud's tags change.
public enum BoardColumnMenuItem: CaseIterable, Sendable {
    case moveLeft, moveRight, remove

    /// The first item of a group after the first.
    public var startsGroup: Bool { self == .remove }

    public var title: String {
        switch self {
        case .moveLeft: return "Move left"
        case .moveRight: return "Move right"
        case .remove: return "Remove column"
        }
    }

    public func isEnabled(for tag: String, in columns: BoardColumns) -> Bool {
        switch self {
        case .moveLeft: return columns.canMoveLeft(tag)
        case .moveRight: return columns.canMoveRight(tag)
        case .remove: return columns.has(tag)
        }
    }

    public func apply(to columns: inout BoardColumns, for tag: String) {
        switch self {
        case .moveLeft: columns.moveLeft(tag)
        case .moveRight: columns.moveRight(tag)
        case .remove: columns.remove(tag)
        }
    }
}

// MARK: dragging a column

/// A gap between the tag columns, where a dragged column lands: before the `gap`th tag column,
/// or after the last one when `gap` is their count.
public struct BoardColumnDrop: Equatable, Sendable {
    public var gap: Int

    public init(gap: Int) {
        self.gap = gap
    }

    /// Which edge of a column the drop line is drawn on: the leading edge of the column at the
    /// gap, or the trailing edge of the last one.
    public enum Line: Sendable { case before, after }

    public func line(on tag: String, in tags: [String]) -> Line? {
        if gap < tags.count { return BudTags.key(tags[gap]) == BudTags.key(tag) ? .before : nil }
        return tags.last.map(BudTags.key) == BudTags.key(tag) ? .after : nil
    }

    /// The place the moved column takes, since the gaps count its old place too.
    public func index(moving tag: String, in tags: [String]) -> Int {
        if let i = tags.firstIndex(where: { BudTags.key($0) == BudTags.key(tag) }), i < gap {
            return gap - 1
        }
        return gap
    }

    /// The gap under a point: after every column whose middle is left of it, from the columns'
    /// frames in the same space as the point.
    public static func under(_ point: CGPoint, frames: [String: CGRect], tags: [String]) -> BoardColumnDrop {
        var gap = 0
        for (i, tag) in tags.enumerated() {
            if let frame = frames[tag], frame.midX <= point.x { gap = i + 1 }
        }
        return BoardColumnDrop(gap: gap)
    }
}

/// A tag column in hand: which, where the pointer is, and the gap it would land in.
public struct BoardColumnDrag: Equatable, Sendable {
    public var tag: String
    public var point: CGPoint
    public var drop: BoardColumnDrop?

    public init(tag: String, point: CGPoint, drop: BoardColumnDrop? = nil) {
        self.tag = tag
        self.point = point
        self.drop = drop
    }

    /// Where the drop line is drawn on a column; none for a gap beside the column in hand,
    /// where a drop changes nothing.
    public func line(on target: String, in tags: [String]) -> BoardColumnDrop.Line? {
        guard let drop else { return nil }
        if let i = tags.firstIndex(where: { BudTags.key($0) == BudTags.key(tag) }), drop.gap == i || drop.gap == i + 1 {
            return nil
        }
        return drop.line(on: target, in: tags)
    }
}

#if canImport(SwiftUI)
// MARK: through the store

extension BudStore {
    /// The columns of a bud's board as the vault holds them, or the default spelled out: the
    /// tags in use. An edit starts from this, so a column taken off a default board stays off.
    public func boardColumns(of id: UUID) -> BoardColumns {
        boards[id] ?? BoardColumns(tags: BoardColumns.inUse(by: tree.walk(under: id)))
    }

    /// Edits a bud's board columns and keeps them, so every device shows the same board.
    public func editBoardColumns(of id: UUID, _ edit: (inout BoardColumns) -> Void) {
        var columns = boardColumns(of: id)
        edit(&columns)
        setBoardColumns(columns, of: id)
    }

    /// Adds a column for `tag` at the end of a bud's board.
    public func addBoardColumn(_ tag: String, of id: UUID) {
        editBoardColumns(of: id) { $0.add(tag) }
    }

    /// Takes a column off a bud's board; the buds keep the tag.
    public func removeBoardColumn(_ tag: String, of id: UUID) {
        editBoardColumns(of: id) { $0.remove(tag) }
    }

    /// Moves a column to a place among a bud's tag columns.
    public func moveBoardColumn(_ tag: String, to index: Int, of id: UUID) {
        editBoardColumns(of: id) { $0.move(tag, to: index) }
    }

    /// What Add column offers on a bud's board for what is typed.
    public func boardTagChoices(for query: String, of id: UUID) -> BoardTagChoices {
        BoardTagChoices.rows(for: query, columns: boardColumns(of: id), inside: tree.walk(under: id), counts: tree.tagCounts())
    }
}
#endif
