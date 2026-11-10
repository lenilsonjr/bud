import Foundation

/// A lens the person named and kept: the question the canvas was asked, under a name, so it can
/// be asked again from the lens menu or opened as a page in Files. Each one sits in the vault's
/// `lenses` map under its own id, so every device offers the same.
public struct SavedLens: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var query: LensQuery
    /// The question as the vault held it, when a newer build wrote something this one cannot
    /// read: the query then matches nothing, and a rename writes this text back untouched so
    /// the newer device keeps what it asked. Nil for a question read in full.
    public let foreign: String?

    public init(id: UUID = UUID(), name: String, query: LensQuery) {
        self.init(id: id, name: name, query: query, foreign: nil)
    }

    private init(id: UUID, name: String, query: LensQuery, foreign: String?) {
        self.id = id
        self.name = name
        self.query = query
        self.foreign = foreign
    }

    /// A name as it is kept: trimmed, nil when nothing is left.
    public static func clean(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Why a question cannot be kept, in words for the menu; nil when it can.
    public static func refusal(query: LensQuery?, saved: [SavedLens]) -> String? {
        guard let query, !query.isEmpty else { return "Tick a row to save a lens" }
        if query.never { return "Nothing can match these rows" }
        if let same = saved.first(where: { $0.query == query }) { return "Saved already as \(same.name)" }
        return nil
    }

    /// Why a question cannot be kept under a name; nil when it can.
    public static func refusal(name: String, query: LensQuery?, saved: [SavedLens]) -> String? {
        refusal(query: query, saved: saved) ?? (clean(name) == nil ? "Give the lens a name" : nil)
    }

    /// What the vault holds under the lens's id: its name and its question, as JSON.
    private struct Entry: Codable {
        var name: String
        var query: LensQuery
    }

    /// The text the vault keeps for the lens: its name, and its question as it was read when
    /// this build could not read all of it.
    public var text: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        if let foreign {
            guard let name = try? encoder.encode(name) else { return nil }
            return #"{"name":"# + String(decoding: name, as: UTF8.self) + #","query":"# + foreign + "}"
        }
        return (try? encoder.encode(Entry(name: name, query: query))).map { String(decoding: $0, as: UTF8.self) }
    }

    /// The lenses the vault's map holds, sorted by name. An entry whose key is not an id, or
    /// whose text is not a name and a question at all, is skipped.
    public static func read(_ stored: [String: String]) -> [SavedLens] {
        let lenses = stored.compactMap { key, text -> SavedLens? in
            guard let id = UUID(uuidString: key) else { return nil }
            let unknown = LensQuery.Unknown()
            let decoder = JSONDecoder()
            decoder.userInfo[LensQuery.Unknown.key] = unknown
            guard let entry = try? decoder.decode(Entry.self, from: Data(text.utf8)),
                  let name = clean(entry.name) else { return nil }
            var foreign: String? = nil
            if unknown.found {
                guard let raw = rawQuery(in: text) else { return nil }
                foreign = raw
            }
            return SavedLens(id: id, name: name, query: entry.query, foreign: foreign)
        }
        return sorted(lenses)
    }

    /// The question of an entry as JSON text, whatever it holds.
    private static func rawQuery(in text: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let query = object["query"],
              let data = try? JSONSerialization.data(withJSONObject: query, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(decoding: data, as: UTF8.self)
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
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, state, day, pinned, holdsOpen, tags, linked, grown, source, never
    }

    /// Any key, to find the ones this build does not know.
    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Told, through the decoder, that a question held something this build cannot read.
    final class Unknown: @unchecked Sendable {
        static let key = CodingUserInfoKey(rawValue: "lensQueryUnknown")!
        var found = false
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        var unknown = try decoder.container(keyedBy: AnyKey.self).allKeys.contains { !known.contains($0.stringValue) }
        // A value this build knows by name, or a mark that it met one it does not.
        func named<T: RawRepresentable>(_ key: CodingKeys, _: T.Type) throws -> T? where T.RawValue == String {
            guard let raw = try c.decodeIfPresent(String.self, forKey: key) else { return nil }
            guard let value = T(rawValue: raw) else {
                unknown = true
                return nil
            }
            return value
        }
        self.init(
            kind: try named(.kind, Kind.self),
            state: try named(.state, BudState.self),
            day: try named(.day, Day.self),
            pinned: try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false,
            holdsOpen: try c.decodeIfPresent(Bool.self, forKey: .holdsOpen) ?? false,
            tags: Set(try c.decodeIfPresent([String].self, forKey: .tags) ?? []),
            linked: Set(try c.decodeIfPresent([UUID].self, forKey: .linked) ?? []),
            grown: try c.decodeIfPresent(Bool.self, forKey: .grown) ?? false,
            source: try c.decodeIfPresent(String.self, forKey: .source)
        )
        // Two answers asked of one slot leave nothing to read back, so it is kept as it is. A
        // part this build cannot read matches nothing rather than being left out, which would
        // ask a broader question than the one saved.
        never = try c.decodeIfPresent(Bool.self, forKey: .never) ?? false
        if unknown {
            never = true
            (decoder.userInfo[Unknown.key] as? Unknown)?.found = true
        }
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
