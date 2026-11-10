import Foundation

/// A lens the person named and kept: the question the canvas was asked, under a name, so it can
/// be asked again from the lens menu or opened as a page in Files. Each one sits in the vault's
/// `lenses` map under its own id, so every device offers the same.
public struct SavedLens: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var query: LensQuery

    public init(id: UUID = UUID(), name: String, query: LensQuery) {
        self.id = id
        self.name = name
        self.query = query
    }

    /// A name as it is kept: trimmed, nil when nothing is left.
    public static func clean(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// What the vault holds under the lens's id: its name and its question, as JSON.
    private struct Entry: Codable {
        var name: String
        var query: LensQuery
    }

    /// The text the vault keeps for the lens.
    public var text: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(Entry(name: name, query: query))).map { String(decoding: $0, as: UTF8.self) }
    }

    /// The lenses the vault's map holds, sorted by name. An entry whose key is not an id, or
    /// whose text another build wrote badly, is skipped.
    public static func read(_ stored: [String: String]) -> [SavedLens] {
        let decoder = JSONDecoder()
        let lenses = stored.compactMap { key, text -> SavedLens? in
            guard let id = UUID(uuidString: key),
                  let entry = try? decoder.decode(Entry.self, from: Data(text.utf8)),
                  let name = clean(entry.name) else { return nil }
            return SavedLens(id: id, name: name, query: entry.query)
        }
        return sorted(lenses)
    }

    /// By name, in any case; two of one name by id, so the order is the same on every device.
    public static func sorted(_ lenses: [SavedLens]) -> [SavedLens] {
        lenses.sorted { a, b in
            let x = a.name.lowercased(), y = b.name.lowercased()
            return x != y ? x < y : a.id.uuidString < b.id.uuidString
        }
    }

    /// The name "Save lens…" offers for ticked rows: their names, joined.
    public static func suggestedName(_ names: [String]) -> String {
        names.joined(separator: ", ")
    }
}

/// A question as the vault keeps it: only the facets that are set, under stable keys, the sets
/// sorted so the same question always reads the same.
extension LensQuery: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, state, day, pinned, holdsOpen, tags, linked, grown, source, never
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try c.decodeIfPresent(String.self, forKey: .kind).flatMap(Kind.init(rawValue:)),
            state: try c.decodeIfPresent(String.self, forKey: .state).flatMap(BudState.init(rawValue:)),
            day: try c.decodeIfPresent(String.self, forKey: .day).flatMap(Day.init(rawValue:)),
            pinned: try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false,
            holdsOpen: try c.decodeIfPresent(Bool.self, forKey: .holdsOpen) ?? false,
            tags: Set(try c.decodeIfPresent([String].self, forKey: .tags) ?? []),
            linked: Set(try c.decodeIfPresent([UUID].self, forKey: .linked) ?? []),
            grown: try c.decodeIfPresent(Bool.self, forKey: .grown) ?? false,
            source: try c.decodeIfPresent(String.self, forKey: .source)
        )
        // Two answers asked of one slot leave nothing to read back, so it is kept as it is.
        never = try c.decodeIfPresent(Bool.self, forKey: .never) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(kind?.rawValue, forKey: .kind)
        try c.encodeIfPresent(state?.rawValue, forKey: .state)
        try c.encodeIfPresent(day?.rawValue, forKey: .day)
        if pinned { try c.encode(true, forKey: .pinned) }
        if holdsOpen { try c.encode(true, forKey: .holdsOpen) }
        if !tags.isEmpty { try c.encode(tags.sorted(), forKey: .tags) }
        if !linked.isEmpty { try c.encode(linked.sorted { $0.uuidString < $1.uuidString }, forKey: .linked) }
        if grown { try c.encode(true, forKey: .grown) }
        try c.encodeIfPresent(source, forKey: .source)
        if never { try c.encode(true, forKey: .never) }
    }
}

extension LensFacet {
    /// The menu rows that ask a question, so a saved lens can be ticked again: the built-ins in
    /// the menu's order, then the tags, the source and the linked buds. A part no row asks (a
    /// note, Overdue, holds an open to-do) is left out; `title` names a linked bud.
    public static func facets(of query: LensQuery, title: (UUID) -> String) -> [LensFacet] {
        var out: [LensFacet] = []
        var query = query
        if query.kind == .todo, query.state == .open {
            out.append(.openTodos)
            query.kind = nil
            query.state = nil
        }
        if query.day == .today { out.append(.dueToday) }
        if query.grown { out.append(.recentlyGrown) }
        if query.pinned { out.append(.pinned) }
        if query.kind == nil, query.state == .done { out.append(.done) }
        out += query.tags.sorted().map { .tag($0) }
        if let source = query.source { out.append(.source(source)) }
        out += query.linked.sorted { $0.uuidString < $1.uuidString }.map { .linked($0, title: title($0)) }
        return out
    }
}
