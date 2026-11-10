import Foundation

/// What dropping a card on a column writes to the bud's front matter, and nothing else: in a
/// tag column the column's tag goes into its list and the other columns' tags come out; in Done
/// it closes; in Cancelled it closes with the cancelled mark; back in Open the column tags come
/// out and a closed one reopens. A `#tag` in the body is the bud's text and stays where it is.
public struct BoardDrop: Equatable, Sendable {
    /// The column tags taken out of the bud's own list, as written there.
    public var removed: [String] = []
    /// The column's tag put into the list; nil when the bud carries it already.
    public var added: String?
    /// The state the drop writes; nil keeps the one there.
    public var state: BudState?
    /// The cancelled mark: true writes it, false clears it, nil leaves it.
    public var cancelled: Bool?

    public init(removed: [String] = [], added: String? = nil, state: BudState? = nil, cancelled: Bool? = nil) {
        self.removed = removed
        self.added = added
        self.state = state
        self.cancelled = cancelled
    }

    /// Whether the drop would write nothing.
    public var isEmpty: Bool { removed.isEmpty && added == nil && state == nil && cancelled == nil }

    /// The drop of `bud` on `column`, with `columns` the tags that have a column on the board;
    /// nil when the card sits in that column already and nothing would change. Whether the
    /// card may land there is `refusal`.
    public static func of(_ bud: Bud, on column: BoardColumn.Kind, columns: [String]) -> BoardDrop? {
        var drop = BoardDrop()
        let keys = Set(columns.map(BudTags.key))
        switch column {
        case .open, .tag:
            var target: String?
            if case .tag(let tag) = column { target = tag }
            let key = target.map(BudTags.key)
            drop.removed = bud.tags.filter { keys.contains(BudTags.key($0)) && BudTags.key($0) != key }
            if let target, !bud.carries(target) { drop.added = target }
            if bud.isDone { drop.state = .open }
            if bud.isCancelled { drop.cancelled = false }
        case .done:
            if !bud.isDone { drop.state = .done }
            if bud.isCancelled { drop.cancelled = false }
        case .cancelled:
            if !bud.isDone { drop.state = .done }
            if !bud.isCancelled { drop.cancelled = true }
        }
        return drop.isEmpty ? nil : drop
    }

    /// Why `bud` cannot land on `column`, as the toast says it; nil when it can. A planted bud's
    /// cancelled mark is its source's: the live sync writes it back, so a drop may not change
    /// it. A `#tag` in the body is text a drop never edits, so a card whose body names another
    /// column stays in that column whatever its list says.
    public static func refusal(of bud: Bud, on column: BoardColumn.Kind, columns: [String]) -> String? {
        guard let drop = of(bud, on: column, columns: columns) else { return nil }
        if drop.cancelled != nil, bud.from != nil {
            return "\(bud.text) follows its source: cancelled is its source's to set"
        }
        let landing = Self.column(of: drop.applied(to: bud), columns: columns)
        guard landing != column else { return nil }
        if case .tag(let tag) = landing {
            return "\(bud.text) stays in #\(tag): its text says #\(tag)"
        }
        return "\(bud.text) cannot go there"
    }

    /// The column a bud sits in on a board with `columns`: Cancelled and Done first, whatever it
    /// carries, then the first column tag among all its tags, else Open. The rule `Board` lays
    /// the cards out by.
    public static func column(of bud: Bud, columns: [String]) -> BoardColumn.Kind {
        if bud.isCancelled { return .cancelled }
        if bud.isDone { return .done }
        let carried = Set(bud.allTags.map(BudTags.key))
        if let tag = columns.first(where: { carried.contains(BudTags.key($0)) }) { return .tag(tag) }
        return .open
    }

    /// The bud as the drop leaves it.
    public func applied(to bud: Bud) -> Bud {
        var after = bud
        after.tags.removeAll { tag in removed.contains { BudTags.key($0) == BudTags.key(tag) } }
        if let added, !after.tags.contains(where: { BudTags.key($0) == BudTags.key(added) }) { after.tags.append(added) }
        if let state { after.state = state }
        if let cancelled { after.fromState = cancelled ? "cancelled" : nil }
        return after
    }

    /// The bud as the undo leaves it, from `before`, the bud as it was: the tag the drop put in
    /// comes out, the tags it took out return to their old places, and the state and the mark go
    /// back. Anything else that changed since, a tag added by hand say, stays.
    public func undone(_ bud: Bud, before: Bud) -> Bud {
        var after = bud
        if let added { after.tags.removeAll { BudTags.key($0) == BudTags.key(added) } }
        for tag in removed where !after.tags.contains(where: { BudTags.key($0) == BudTags.key(tag) }) {
            let index = before.tags.firstIndex { BudTags.key($0) == BudTags.key(tag) } ?? after.tags.count
            after.tags.insert(tag, at: min(index, after.tags.count))
        }
        if state != nil { after.state = before.state }
        if cancelled != nil { after.fromState = before.fromState }
        return after
    }

    /// The line under the pointer while a card is held over a column: "Drop to close it".
    public static func hint(on column: BoardColumn.Kind) -> String {
        switch column {
        case .open: return "Drop to open it"
        case .tag(let tag): return "Drop to tag it #\(tag)"
        case .done: return "Drop to close it"
        case .cancelled: return "Drop to cancel it"
        }
    }

    /// What the toast says once the card has landed: "Closed Printer quote".
    public static func message(on column: BoardColumn.Kind, title: String) -> String {
        switch column {
        case .open: return "Moved \(title) to Open"
        case .tag(let tag): return "Tagged \(title) #\(tag)"
        case .done: return "Closed \(title)"
        case .cancelled: return "Cancelled \(title)"
        }
    }

    /// What the toast says when the vault refused part of the drop: "Couldn't move Printer
    /// quote to Done".
    public static func failure(on column: BoardColumn.Kind, title: String) -> String {
        "Couldn't move \(title) to \(BoardColumn(kind: column, cards: []).title)"
    }

    /// Writes the drop to the bud's file, one property at a time: the state and the mark first,
    /// which a vault never refuses, then the tag edits, which it may.
    public func write(to vault: Vault, at path: String) async throws {
        if let state { try await vault.setState(path, state) }
        if let cancelled { try await vault.setFromState(path, cancelled ? "cancelled" : nil) }
        for tag in removed { _ = try await vault.removeTag(path, tag) }
        if let added { try await vault.addTag(path, added) }
    }

    /// Puts the file back as `before` carried it: the state and the mark go back, the tag the
    /// drop put in comes out, and the tags it took out return to their places in the list. A
    /// vault only adds at the end, so when they sat elsewhere the list is written over in order.
    public func undo(to vault: Vault, at path: String, before: Bud) async throws {
        if state != nil { try await vault.setState(path, before.state) }
        if cancelled != nil { try await vault.setFromState(path, before.fromState) }
        if let added { _ = try await vault.removeTag(path, added) }
        guard !removed.isEmpty else { return }
        if before.tags.suffix(removed.count) == removed {
            for tag in removed { try await vault.addTag(path, tag) }
        } else {
            let kept = before.tags.filter { tag in !removed.contains { BudTags.key($0) == BudTags.key(tag) } }
            for tag in kept { _ = try await vault.removeTag(path, tag) }
            for tag in before.tags { try await vault.addTag(path, tag) }
        }
    }
}

extension Tree {
    /// Applies a drop to a bud here, as the vault will write it.
    public mutating func apply(_ drop: BoardDrop, to id: UUID) {
        guard let i = buds.firstIndex(where: { $0.id == id }) else { return }
        buds[i] = drop.applied(to: buds[i])
    }

    /// Takes a drop back here: the inverse of `apply`, from `before`, the bud as it was.
    public mutating func undo(_ drop: BoardDrop, on id: UUID, before: Bud) {
        guard let i = buds.firstIndex(where: { $0.id == id }) else { return }
        buds[i] = drop.undone(buds[i], before: before)
    }
}

extension Board {
    /// The tags that have a column, in column order.
    public var columnTags: [String] { columns.compactMap(\.tag) }

    /// The card of a bud, in whichever column it sits, Cancelled included.
    public func card(_ id: UUID) -> BoardCard? {
        for column in columns + [cancelled] {
            if let card = column.cards.first(where: { $0.id == id }) { return card }
        }
        return nil
    }
}
