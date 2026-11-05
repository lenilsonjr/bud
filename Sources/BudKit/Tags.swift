import Foundation

/// Tags, read the way the core reads them (core/bud-core/src/tags.rs): the list in a bud's
/// frontmatter, which a vault hands over, and the `#tags` in its body's prose. Spellings that
/// differ only in case are one tag. The reading walks Unicode scalars, as the core walks chars,
/// so a combining mark or a keycap ends a tag in both.
public enum BudTags {
    /// A scalar a tag can hold: a letter, a digit, `_`, `-` or `/` (for nested tags).
    static func isTagScalar(_ s: Unicode.Scalar) -> Bool {
        s.properties.isAlphabetic || s.properties.numericType != nil || s == "_" || s == "-" || s == "/"
    }

    /// A tag as written, without a leading `#` and trailing `/`; nil when it holds no letter
    /// (`#1` and `#-` are not tags) or anything a tag cannot.
    public static func clean(_ raw: String) -> String? {
        var tag = Substring(raw.trimmingCharacters(in: .whitespacesAndNewlines)).unicodeScalars
        tag = tag.drop { $0 == "#" }
        while tag.last == "/" { tag = tag.dropLast() }
        guard tag.allSatisfy(isTagScalar), tag.contains(where: \.properties.isAlphabetic) else { return nil }
        return String(tag)
    }

    /// What two spellings of one tag share: the tag in lower case, a final sigma as `ς`, as the
    /// core lowers it.
    public static func key(_ tag: String) -> String {
        let scalars = Array(tag.unicodeScalars)
        var out = String.UnicodeScalarView()
        for (i, s) in scalars.enumerated() {
            guard s == "\u{03A3}" else {
                out.append(contentsOf: s.properties.lowercaseMapping.unicodeScalars)
                continue
            }
            func cased(_ side: some Sequence<Unicode.Scalar>) -> Bool {
                side.first { !$0.properties.isCaseIgnorable }?.properties.isCased ?? false
            }
            let final = cased(scalars[..<i].reversed()) && !cased(scalars[(i + 1)...])
            out.append(final ? "\u{03C2}" : "\u{03C3}")
        }
        return String(out)
    }

    /// The `#tags` in a body's prose: a `#` at the start of a line or after a space or a comma,
    /// then tag characters. A heading's `# ` is not a tag, nor is a `#` inside a word or a link,
    /// nor anything in code.
    public static func inBody(_ body: String) -> [String] {
        spans(body).map(\.tag)
    }

    /// Each body `#tag` with the line it is on and the scalar offset of its first scalar after
    /// the `#`.
    static func spans(_ body: String) -> [(line: Int, start: Int, tag: String)] {
        var out: [(line: Int, start: Int, tag: String)] = []
        for line in BudLinks.prose(body) {
            // Code reads as spaces, scalar for scalar, so offsets stay offsets into the line.
            var scalars: [Unicode.Scalar] = []
            for (written, blank) in zip(line.written, line.blank) {
                let own = Array(written.unicodeScalars)
                scalars += written == blank ? own : Array(repeating: " ", count: own.count)
            }
            var previous: Unicode.Scalar?
            var i = 0
            while i < scalars.count {
                let s = scalars[i]
                if s == "#", previous.map({ $0.properties.isWhitespace || $0 == "," }) ?? true {
                    let run = scalars[(i + 1)...].prefix(while: isTagScalar)
                    var text = String.UnicodeScalarView()
                    text.append(contentsOf: run)
                    if let tag = clean(String(text)) { out.append((line.index, i + 1, tag)) }
                    previous = run.last ?? "#"
                    i += 1 + run.count
                    continue
                }
                previous = s
                i += 1
            }
        }
        return out
    }

    /// The frontmatter tags then the body's, each tag once, the first spelling kept.
    public static func all(front: [String], body: String) -> [String] {
        var seen: Set<String> = []
        return (front + inBody(body)).filter { seen.insert(key($0)).inserted }
    }

    /// `tag` with `from`, in any case, swapped for `to` when it is `from` or nested under it.
    static func renamed(_ tag: String, from: String, to: String) -> String? {
        let scalars = tag.unicodeScalars
        let cut = scalars.index(scalars.startIndex, offsetBy: from.unicodeScalars.count, limitedBy: scalars.endIndex) ?? scalars.endIndex
        let head = String(scalars[..<cut])
        let rest = String(scalars[cut...])
        guard key(head) == key(from), rest.isEmpty || rest.hasPrefix("/") else { return nil }
        return to + rest
    }

    /// A frontmatter list after a rename: renamed tags take the new name, and one that lands on
    /// a tag the list has already merges into it. Other repeats the list has stay.
    static func renaming(_ tags: [String], from: String, to: String) -> [String] {
        let new = tags.map { renamed($0, from: from, to: to) }
        let landed = Set(new.compactMap { $0.map(key) })
        var seen: Set<String> = []
        return zip(tags, new).map { $1 ?? $0 }.filter { !landed.contains(key($0)) || seen.insert(key($0)).inserted }
    }

    /// `body` with every `#from`, and every tag nested under it, renamed to `to`; nil when it has
    /// none.
    static func renaming(body: String, from: String, to: String) -> String? {
        let hits = spans(body).compactMap { span in
            renamed(span.tag, from: from, to: to).map { (span.line, span.start, span.tag.unicodeScalars.count, $0) }
        }
        guard !hits.isEmpty else { return nil }
        // Lines split on "\n" alone keep a "\r" at their end, so each keeps its ending.
        var lines = body.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false).map(Array.init)
        for (line, start, count, new) in hits.reversed() {
            lines[line].replaceSubrange(start..<start + count, with: Array(new.unicodeScalars))
        }
        var out = String.UnicodeScalarView()
        for (i, line) in lines.enumerated() {
            if i > 0 { out.append("\n") }
            out.append(contentsOf: line)
        }
        return String(out)
    }
}

/// A tag and how many buds carry it.
public struct TagCount: Hashable, Sendable {
    public var tag: String
    public var buds: Int

    public init(tag: String, buds: Int) {
        self.tag = tag
        self.buds = buds
    }
}

/// One bud a tag rename changed: its text before and after, as the vault writes it.
/// `restoreText` puts `before` back while the bud still holds `after`.
public struct TagEditRecord: Hashable, Sendable {
    public var path: String
    public var before: String
    public var after: String

    public init(path: String, before: String, after: String) {
        self.path = path
        self.before = before
        self.after = after
    }
}

extension Bud {
    /// Every tag the bud carries: its own list, then the `#tags` in its body.
    public var allTags: [String] { BudTags.all(front: tags, body: body) }

    /// Whether the bud carries `tag`, in any case.
    public func carries(_ tag: String) -> Bool {
        allTags.contains { BudTags.key($0) == BudTags.key(tag) }
    }
}

extension Tree {
    /// Every tag outside the Trash with the number of buds that carry it, most used first, each
    /// shown the way most of its buds write it.
    public func tagCounts() -> [TagCount] {
        var spellings: [String: [String: Int]] = [:]
        var order: [String] = []
        for bud in buds where bud.id != rootID && bud.id != inboxID {
            for tag in bud.allTags {
                let key = BudTags.key(tag)
                if spellings[key] == nil { order.append(key) }
                spellings[key, default: [:]][tag, default: 0] += 1
            }
        }
        let counts = order.map { key -> TagCount in
            let ways = spellings[key]!
            let shown = ways.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }!.key
            return TagCount(tag: shown, buds: ways.values.reduce(0, +))
        }
        return counts.sorted { a, b in
            a.buds != b.buds ? a.buds > b.buds : BudTags.key(a.tag) < BudTags.key(b.tag)
        }
    }

    /// Adds `tag` to a bud's own list unless the list has it already, in any case: at the end,
    /// or at `index` when there is one.
    public mutating func addTag(_ id: UUID, _ tag: String, at index: Int? = nil) {
        guard let tag = BudTags.clean(tag), let i = buds.firstIndex(where: { $0.id == id }),
              !buds[i].tags.contains(where: { BudTags.key($0) == BudTags.key(tag) }) else { return }
        buds[i].tags.insert(tag, at: min(index ?? buds[i].tags.count, buds[i].tags.count))
    }

    /// Takes `tag`, in any case, out of a bud's own list. A `#tag` in its body stays.
    public mutating func removeTag(_ id: UUID, _ tag: String) {
        guard let i = buds.firstIndex(where: { $0.id == id }) else { return }
        buds[i].tags.removeAll { BudTags.key($0) == BudTags.key(tag) }
    }

    /// Renames `from` to `to` in every bud outside the Trash, lists and bodies alike, with the
    /// tags nested under it. Returns the buds it changed.
    @discardableResult
    public mutating func renameTag(_ from: String, to: String) -> [UUID] {
        guard let from = BudTags.clean(from), let to = BudTags.clean(to), from != to else { return [] }
        var changed: [UUID] = []
        for i in buds.indices {
            let tags = BudTags.renaming(buds[i].tags, from: from, to: to)
            let body = BudTags.renaming(body: buds[i].body, from: from, to: to)
            guard tags != buds[i].tags || body != nil else { continue }
            buds[i].tags = tags
            if let body { buds[i].body = body }
            changed.append(buds[i].id)
        }
        return changed
    }
}

/// What the tag picker offers for what is typed: tags in use whose name holds it, in any case,
/// those that start with it first, each with its bud count; then creating it, when it is a tag
/// no bud uses yet. Tags the bud carries already are left out.
public struct TagChoices {
    public enum Row: Hashable, Sendable {
        case tag(TagCount)
        case create(String)
    }

    public static func rows(for query: String, in counts: [TagCount], excluding carried: [String], limit: Int = 6) -> [Row] {
        let typed = query.trimmingCharacters(in: .whitespaces).drop { $0 == "#" }
        let wanted = BudTags.key(String(typed))
        let skip = Set(carried.map(BudTags.key))
        let found = counts.filter { count in
            let key = BudTags.key(count.tag)
            return !skip.contains(key) && (wanted.isEmpty || key.contains(wanted))
        }
        let starting = found.filter { BudTags.key($0.tag).hasPrefix(wanted) }
        let inside = found.filter { !BudTags.key($0.tag).hasPrefix(wanted) }
        var rows = (starting + inside).prefix(limit).map(Row.tag)
        let taken = counts.contains { BudTags.key($0.tag) == wanted } || skip.contains(wanted)
        if let tag = BudTags.clean(String(typed)), !taken { rows.append(.create(tag)) }
        return rows
    }
}

/// One chip under a page's title: a tag of the bud's own list, which can be taken off, or a
/// `#tag` written in its body, which stays until the text changes.
public struct TagChip: Hashable, Sendable {
    public var tag: String
    public var inText: Bool
}

extension Bud {
    /// The chips under the page title: the bud's own list, then the body's tags it lacks.
    public var tagChips: [TagChip] {
        let own = Set(tags.map(BudTags.key))
        var seen: Set<String> = []
        return tags.filter { seen.insert(BudTags.key($0)).inserted }.map { TagChip(tag: $0, inText: false) }
            + BudTags.inBody(body).filter { !own.contains(BudTags.key($0)) && seen.insert(BudTags.key($0)).inserted }
                .map { TagChip(tag: $0, inText: true) }
    }
}
