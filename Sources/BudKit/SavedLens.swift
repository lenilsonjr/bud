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

    /// Whether two lenses ask one question: the same query, or the same text from a newer
    /// build.
    public func asksSame(as other: SavedLens) -> Bool {
        foreign == nil && other.foreign == nil ? query == other.query : foreign == other.foreign
    }

    /// The lens after a tag rename, when its question asks for the tag or one nested under it;
    /// nil when it does not, or when a newer build wrote it and its text stays as it is.
    public func renamingTag(_ from: String, to: String) -> SavedLens? {
        guard foreign == nil else { return nil }
        let tags = Set(query.tags.map { BudTags.renamed($0, from: from, to: to) ?? $0 }.map(BudTags.key))
        guard tags != query.tags else { return nil }
        var out = self
        out.query.tags = tags
        return out
    }

    /// The text the vault keeps for the lens: its name, and its question as it was read when
    /// this build could not read all of it.
    public var text: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if let foreign {
            guard let name = try? encoder.encode(name) else { return nil }
            return #"{"name":"# + String(decoding: name, as: UTF8.self) + #","query":"# + foreign + "}"
        }
        return (try? encoder.encode(Entry(name: name, query: query))).map { String(decoding: $0, as: UTF8.self) }
    }

    /// The lenses the vault's map holds, sorted by name. An entry whose key is not an id is
    /// skipped; every other one shows, so it can be deleted: one with no name is untitled, and
    /// one whose question this build cannot read matches nothing and keeps its text.
    public static func read(_ stored: [String: String]) -> [SavedLens] {
        let lenses = stored.compactMap { key, text -> SavedLens? in
            guard let id = UUID(uuidString: key) else { return nil }
            var nothing = LensQuery()
            nothing.never = true
            guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
                // Not an entry at all: the whole text is kept as the question, as a string.
                return SavedLens(id: id, name: untitled, query: nothing, foreign: quoted(text))
            }
            let name = (object["name"] as? String).flatMap(clean) ?? untitled
            guard let raw = json(object["query"] ?? NSNull()) else {
                return SavedLens(id: id, name: name, query: nothing, foreign: quoted(text))
            }
            let unknown = LensQuery.Unknown()
            let decoder = JSONDecoder()
            decoder.userInfo[LensQuery.Unknown.key] = unknown
            // An empty question would light everything: no build saves one, so it is read as
            // one this build cannot read.
            guard let query = try? decoder.decode(LensQuery.self, from: Data(raw.utf8)), !query.isEmpty else {
                return SavedLens(id: id, name: name, query: nothing, foreign: raw)
            }
            return SavedLens(id: id, name: name, query: query, foreign: unknown.found ? raw : nil)
        }
        return sorted(lenses)
    }

    /// A JSON value as text, keys sorted.
    private static func json(_ value: Any) -> String? {
        guard let data = try? JSONSerialization.data(
            withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        ) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Text as a JSON string.
    private static func quoted(_ text: String) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return (try? encoder.encode(text)).map { String(decoding: $0, as: UTF8.self) }
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

    /// The name field after the ticked rows change: a name still as it was offered follows the
    /// rows; one the person typed stays. The second is the name offered now.
    public static func followRows(name: String, suggested: String, rows: [String]) -> (name: String, suggested: String) {
        let next = suggestedName(rows)
        return (name == suggested ? next : name, next)
    }

    /// The saved lenses after a tag rename: each that asks for the tag asks for the new name.
    /// Where the rename makes a lens ask what another already asks, one lens per question
    /// stays, the first by name, and the others go. Only lenses this rename changed bring that
    /// about: duplicates there were before stay as they were, and so does a lens this build
    /// cannot read.
    public static func afterTagRename(_ lenses: [SavedLens], from: String, to: String) -> TagRename {
        var out = TagRename()
        var now: [SavedLens] = []
        var changed: Set<UUID> = []
        for lens in lenses {
            if let renamed = lens.renamingTag(from, to: to) {
                out.asked += 1
                out.renamed.append((lens, renamed))
                changed.insert(lens.id)
                now.append(renamed)
            } else {
                now.append(lens)
            }
        }
        // Each readable question a changed lens now asks, with every lens asking it.
        let readable = sorted(now).filter { $0.foreign == nil }
        var questions: [LensQuery] = []
        for lens in readable where changed.contains(lens.id) && !questions.contains(lens.query) {
            questions.append(lens.query)
        }
        for question in questions {
            let asking = readable.filter { $0.query == question }
            let unchanged = asking.filter { !changed.contains($0.id) }
            // Duplicates from before stay; the changed lenses join the first of them. Otherwise
            // the first by name stays.
            let stays = unchanged.count > 1 ? unchanged : [asking[0]]
            for lens in asking where !stays.contains(where: { $0.id == lens.id }) {
                let before = lenses.first { $0.id == lens.id } ?? lens
                out.merged.append((before, stays[0]))
                out.renamed.removeAll { $0.after.id == lens.id }
            }
        }
        return out
    }

    /// What a tag rename does to the saved lenses: each renamed lens before and after, and each
    /// that goes, as it was before, with the lens it now asks the same as.
    public struct TagRename {
        public var renamed: [(before: SavedLens, after: SavedLens)] = []
        public var merged: [(gone: SavedLens, into: SavedLens)] = []
        /// How many lenses asked for the tag.
        public var asked = 0
    }

    /// The tag rename's toast: what it reached among the buds and the saved lenses, and the
    /// lenses that went because another now asks the same.
    public static func tagRenameMessage(from: String, to: String, buds: Int, lenses: Int, merged: [(gone: SavedLens, into: SavedLens)]) -> String {
        func count(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? "1 \(one)" : "\(n) \(many)" }
        var reached: [String] = []
        if buds > 0 { reached.append(count(buds, "bud", "buds")) }
        if lenses > 0 { reached.append(count(lenses, "saved lens", "saved lenses")) }
        var message = "Renamed #\(from) to #\(to)"
        if !reached.isEmpty { message += " in " + reached.joined(separator: " and ") }
        if !merged.isEmpty {
            message += ", and merged " + merged.map { "\($0.gone.name) into \($0.into.name)" }.joined(separator: " and ")
        }
        return message
    }

    /// The name a lens shows when the vault holds none it can read.
    public static let untitled = "Untitled lens"
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
        // A value of the type this build expects, or a mark that it met one it does not: a
        // newer build may write a known key in a shape this one cannot read.
        func field<T: Decodable>(_ key: CodingKeys, _: T.Type) -> T? {
            guard c.contains(key), (try? c.decodeNil(forKey: key)) != true else { return nil }
            guard let value = try? c.decode(T.self, forKey: key) else {
                unknown = true
                return nil
            }
            return value
        }
        // A value this build knows by name, or a mark that it met one it does not.
        func named<T: RawRepresentable>(_ key: CodingKeys, _: T.Type) -> T? where T.RawValue == String {
            guard let raw = field(key, String.self) else { return nil }
            guard let value = T(rawValue: raw) else {
                unknown = true
                return nil
            }
            return value
        }
        self.init(
            kind: named(.kind, Kind.self),
            state: named(.state, BudState.self),
            day: named(.day, Day.self),
            pinned: field(.pinned, Bool.self) ?? false,
            holdsOpen: field(.holdsOpen, Bool.self) ?? false,
            tags: Set(field(.tags, [String].self) ?? []),
            linked: Set(field(.linked, [UUID].self) ?? []),
            grown: field(.grown, Bool.self) ?? false,
            source: field(.source, String.self)
        )
        // Two answers asked of one slot leave nothing to read back, so it is kept as it is. A
        // part this build cannot read matches nothing rather than being left out, which would
        // ask a broader question than the one saved.
        never = field(.never, Bool.self) ?? false
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
