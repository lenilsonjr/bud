import Foundation

/// Tags, read the way the core reads them (core/bud-core/src/tags.rs): the list in a bud's
/// frontmatter, which a vault hands over, and the `#tags` in its body's prose. Spellings that
/// differ only in case are one tag.
public enum BudTags {
    /// A character a tag can hold: a letter, a digit, `_`, `-` or `/` (for nested tags).
    static func isTagCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "-" || c == "/"
    }

    /// A tag as written, without a leading `#` and trailing `/`; nil when it holds no letter
    /// (`#1` and `#-` are not tags) or anything a tag cannot.
    public static func clean(_ raw: String) -> String? {
        var tag = Substring(raw.trimmingCharacters(in: .whitespaces))
        tag = tag.drop { $0 == "#" }
        while tag.last == "/" { tag = tag.dropLast() }
        guard tag.allSatisfy(isTagCharacter), tag.contains(where: \.isLetter) else { return nil }
        return String(tag)
    }

    /// What two spellings of one tag share.
    public static func key(_ tag: String) -> String { tag.lowercased() }

    /// The `#tags` in a body's prose: a `#` at the start of a line or after a space or a comma,
    /// then tag characters. A heading's `# ` is not a tag, nor is a `#` inside a word or a link,
    /// nor anything in code.
    public static func inBody(_ body: String) -> [String] {
        spans(body).map(\.tag)
    }

    /// Each body `#tag` with the line it is on and where its first character after the `#` is.
    static func spans(_ body: String) -> [(line: Int, start: Int, tag: String)] {
        var out: [(line: Int, start: Int, tag: String)] = []
        for line in BudLinks.prose(body) {
            let chars = line.blank
            var previous: Character?
            var i = 0
            while i < chars.count {
                let c = chars[i]
                if c == "#", previous.map({ $0.isWhitespace || $0 == "," }) ?? true {
                    let run = chars[(i + 1)...].prefix(while: isTagCharacter)
                    if let tag = clean(String(run)) { out.append((line.index, i + 1, tag)) }
                    previous = run.last ?? "#"
                    i += 1 + run.count
                    continue
                }
                previous = c
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
        let head = String(tag.prefix(from.count))
        let rest = tag.dropFirst(from.count)
        guard key(head) == key(from), rest.isEmpty || rest.first == "/" else { return nil }
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
            renamed(span.tag, from: from, to: to).map { (span.line, span.start, span.tag.count, $0) }
        }
        guard !hits.isEmpty else { return nil }
        var lines = BudLinks.lines(body).map { Array($0) }
        for (line, start, count, new) in hits.reversed() {
            lines[line].replaceSubrange(start..<start + count, with: Array(new))
        }
        // Put each line back with the ending it had.
        var out = ""
        var rest = Substring(body)
        for (i, line) in lines.enumerated() {
            out += String(line)
            let written = BudLinks.lines(body)[i]
            rest = rest.dropFirst(written.count)
            if let end = rest.first {
                out.append(end)
                rest = rest.dropFirst()
            }
        }
        return out
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

/// One bud a tag rename changed: its text before and after, as the vault writes it. `setText`
/// with `before` undoes the rename for that bud.
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

    /// Adds `tag` to a bud's own list unless it carries it already.
    public mutating func addTag(_ id: UUID, _ tag: String) {
        guard let tag = BudTags.clean(tag), let i = buds.firstIndex(where: { $0.id == id }),
              !buds[i].carries(tag) else { return }
        buds[i].tags.append(tag)
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
