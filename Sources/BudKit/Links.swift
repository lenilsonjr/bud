import Foundation

/// `[[Target]]` and `[[Target|label]]` written in a body, read the way the core's link index
/// reads them: never inside code, never an embed (`![[...]]`), never across lines, the
/// `#heading` part left off the target.
public enum BudLinks {
    public struct Written: Equatable, Sendable {
        public var target: String
        public var label: String?
        /// The text a reader sees: the label when there is one, the target otherwise.
        public var shown: String { label ?? target }
    }

    /// A line of prose as written, and the same line with its code spans as spaces: one
    /// character for each, so an offset into one is an offset into the other.
    struct Line {
        var written: [Character]
        var blank: [Character]
    }

    /// The links in a body, in order.
    public static func parse(_ body: String) -> [Written] {
        prose(body).flatMap { links(in: $0.blank).map(\.link) }
    }

    /// Each line of a body outside fenced code. A fence opens on a run of three or more
    /// backticks or tildes and closes on a run of the same character at least as long with
    /// nothing after it.
    static func prose(_ body: String) -> [Line] {
        var fence: (Character, Int)?
        var out: [Line] = []
        for raw in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.hasSuffix("\r") ? raw.dropLast() : raw
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            func run(_ c: Character) -> Int { trimmed.prefix { $0 == c }.count }
            if let (c, len) = fence {
                if run(c) >= len, trimmed.drop(while: { $0 == c }).allSatisfy(\.isWhitespace) { fence = nil }
                continue
            }
            if let c = ["`", "~"].first(where: { run($0) >= 3 }) {
                fence = (c, run(c))
                continue
            }
            let written = Array(line)
            out.append(Line(written: written, blank: blankingCode(written)))
        }
        return out
    }

    /// Each code span, backticks included, as spaces. A run of backticks without a closing run
    /// of exactly as many is plain text.
    private static func blankingCode(_ line: [Character]) -> [Character] {
        var out = line
        func runLength(at i: Int) -> Int { line[i...].prefix { $0 == "`" }.count }
        var i = 0
        while i < line.count {
            guard line[i] == "`" else { i += 1; continue }
            let n = runLength(at: i)
            var j = i + n
            var close: Int?
            while j < line.count {
                guard line[j] == "`" else { j += 1; continue }
                let len = runLength(at: j)
                if len == n { close = j; break }
                j += len
            }
            if let close {
                for k in i..<(close + n) { out[k] = " " }
                i = close + n
            } else {
                i += n
            }
        }
        return out
    }

    /// Each link in a line with the character offsets it takes, brackets included.
    static func links(in line: [Character]) -> [(link: Written, range: Range<Int>)] {
        var out: [(Written, Range<Int>)] = []
        var i = 0
        while i + 1 < line.count {
            guard line[i] == "[", line[i + 1] == "[" else { i += 1; continue }
            var close: Int?
            var j = i + 2
            while j + 1 < line.count {
                if line[j] == "]", line[j + 1] == "]" { close = j; break }
                j += 1
            }
            guard let close else { break }
            let inner = line[(i + 2)..<close]
            if inner.contains("[") || inner.contains("]") {
                i += 1
                continue
            }
            let embed = i > 0 && line[i - 1] == "!"
            if !embed, let link = split(String(inner)) { out.append((link, i..<(close + 2))) }
            i = close + 2
        }
        return out
    }

    /// A line of text cut at its links, for a renderer that draws links its own way.
    public enum Run: Equatable, Sendable {
        case text(String)
        case link(Written)
    }

    /// `text` as plain runs and links, in order; links in code stay plain text.
    public static func runs(_ text: String) -> [Run] {
        let written = Array(text)
        let found = links(in: Self.blankingCode(written))
        var out: [Run] = []
        var i = 0
        for (link, range) in found {
            if range.lowerBound > i { out.append(.text(String(written[i..<range.lowerBound]))) }
            out.append(.link(link))
            i = range.upperBound
        }
        if i < written.count || out.isEmpty { out.append(.text(String(written[i...]))) }
        return out
    }

    /// `text` with each link as the text a reader sees, for a screen that draws links plain.
    public static func shown(_ text: String) -> String {
        runs(text).map { run in
            switch run {
            case .text(let plain): return plain
            case .link(let link): return link.shown
            }
        }.joined()
    }

    private static func split(_ inner: String) -> Written? {
        let parts = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let label = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        let target = (parts[0].split(separator: "#", omittingEmptySubsequences: false).first ?? "")
            .trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return nil }
        return Written(target: target, label: label.isEmpty ? nil : label)
    }

    /// Case folded the way the core's index compares titles: ASCII letters only.
    static func fold(_ text: String) -> String {
        String(text.map { $0.isASCII ? Character($0.lowercased()) : $0 })
    }
}

/// A bud that links to another, with the sentence the first such link sits in, links shown as
/// their text.
public struct Backlink: Equatable, Sendable, Identifiable {
    public var from: UUID
    public var sentence: String
    /// Where the link's text is in the sentence, in characters.
    public var mark: Range<Int>
    public var id: UUID { from }
}

extension Tree {
    /// Where a bud lives, as a row under it shows: its folders under Everything, or under the Inbox.
    public func trail(of id: UUID) -> [String] {
        let above = breadcrumb(of: id)
        return ancestors(of: id).contains(inboxID) ? above : ["Everything"] + above
    }

    /// A bud's place in the vault the way a link may name it: "Launch/Welcome list".
    func linkPath(of id: UUID) -> String {
        (breadcrumb(of: id) + [title(of: id)]).joined(separator: "/")
    }

    /// The bud a link's target names: the one bud with that title, then the one with that title
    /// in any case, then the bud at that path. More than one at the first rank that has any, or
    /// none, is no bud.
    public func resolve(_ target: String) -> UUID? {
        resolve(target, in: TitleIndex(self))
    }

    /// `resolve` against titles read once, for a caller that resolves many targets.
    func resolve(_ target: String, in index: TitleIndex) -> UUID? {
        let bare = target.hasSuffix(".md") ? String(target.dropLast(3)) : target
        func one(_ found: [UUID]) -> UUID?? { found.isEmpty ? nil : .some(found.count == 1 ? found[0] : nil) }
        if let found = one(index.exact[target] ?? []) { return found }
        if let found = one(index.folded[BudLinks.fold(target)] ?? []) { return found }
        // A path ends in the bud's own title, so only buds with that title are walked up.
        let last = bare.split(separator: "/").last.map(String.init) ?? bare
        let named = (index.exact[last] ?? []).filter { let path = linkPath(of: $0); return path == target || path == bare }
        return one(named) ?? nil
    }

    /// The buds that link to `id` in their body, one row each, by where they live.
    public func backlinks(to id: UUID) -> [Backlink] {
        guard let target = bud(id) else { return [] }
        let title = BudLinks.fold(target.text)
        let path = linkPath(of: id)
        // Only a link that could name this bud is resolved, each target once.
        var seen: [String: Bool] = [:]
        func names(_ written: String) -> Bool {
            if let known = seen[written] { return known }
            let bare = written.hasSuffix(".md") ? String(written.dropLast(3)) : written
            let could = BudLinks.fold(written) == title || bare == path
            let known = could && resolve(written) == id
            seen[written] = known
            return known
        }
        var out: [(String, Backlink)] = []
        for bud in buds where bud.id != id && bud.body.contains("[[") {
            found: for line in BudLinks.prose(bud.body) {
                let links = BudLinks.links(in: line.blank)
                for (link, range) in links where names(link.target) {
                    let (sentence, mark) = Self.sentence(around: range, in: line, links: links)
                    out.append((linkPath(of: bud.id), Backlink(from: bud.id, sentence: sentence, mark: mark)))
                    break found
                }
            }
        }
        return out.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// The sentence of `line` that holds the link at `range`, its links shown as their text and
    /// its list, quote or heading mark left off, with where that link's text is in it.
    static func sentence(
        around range: Range<Int>, in line: BudLinks.Line, links: [(link: BudLinks.Written, range: Range<Int>)]
    ) -> (String, Range<Int>) {
        let chars = line.blank
        let ends: Set<Character> = [".", "!", "?"]
        func inLink(_ i: Int) -> Range<Int>? { links.first { $0.range.contains(i) }?.range }
        var start = range.lowerBound
        while start > 0 {
            if let other = inLink(start - 1) { start = other.lowerBound; continue }
            if ends.contains(chars[start - 1]), start == chars.count || chars[start].isWhitespace { break }
            start -= 1
        }
        var end = range.upperBound
        while end < chars.count {
            if let other = inLink(end) { end = other.upperBound; continue }
            let next = end + 1
            if ends.contains(chars[end]), next == chars.count || chars[next].isWhitespace { end = next; break }
            end = next
        }
        var text = ""
        var mark = 0..<0
        var i = start
        while i < end {
            if let found = links.first(where: { $0.range.lowerBound == i }) {
                let shown = found.link.shown
                if found.range == range { mark = text.count..<(text.count + shown.count) }
                text += shown
                i = found.range.upperBound
            } else {
                text.append(line.written[i])
                i += 1
            }
        }
        let rest = text.dropFirst(Self.leadingMark(text))
        let shift = text.count - rest.count + rest.prefix(while: \.isWhitespace).count
        let trimmed = rest.trimmingCharacters(in: .whitespaces)
        let lower = max(0, mark.lowerBound - shift)
        return (trimmed, lower..<min(trimmed.count, lower + mark.count))
    }

    /// How many characters at the start of a sentence are a list, quote or heading mark.
    private static func leadingMark(_ text: String) -> Int {
        let chars = Array(text)
        var i = chars.prefix { $0 == " " || $0 == "\t" }.count
        while i < chars.count, chars[i] == ">" { i += 1; i += chars[i...].prefix { $0 == " " }.count }
        if i < chars.count, "-*+".contains(chars[i]), i + 1 < chars.count, chars[i + 1] == " " { return i + 2 }
        let digits = chars[i...].prefix(while: \.isNumber).count
        if digits > 0, i + digits + 1 < chars.count, ".)".contains(chars[i + digits]), chars[i + digits + 1] == " " {
            return i + digits + 2
        }
        let hashes = chars[i...].prefix { $0 == "#" }.count
        if hashes > 0, i + hashes < chars.count, chars[i + hashes] == " " { return i + hashes + 1 }
        return i
    }
}

/// The `[[` picker's sums: the link being typed in a body, the buds it could name, and the body
/// once one is picked. The editor cannot say where its caret is, so the picker reads the end of
/// the body: an open `[[` on its last line, outside code, with nothing closing it.
public struct LinkPicker: Equatable, Sendable {
    /// What follows the open `[[`, up to the end of the body.
    public var query: String
    /// Where `[[` and the query are in the body, in characters.
    var range: Range<Int>

    /// The link being typed at the end of `body`, if one is: an open `[[` with no `]]`, `|` or
    /// newline after it, not an embed and not in code.
    public init?(typing body: String) {
        let chars = Array(body)
        var i = chars.count - 1
        while i > 0 {
            if chars[i] == "\n" || chars[i] == "|" || (chars[i] == "]" && chars[i - 1] == "]") { return nil }
            if chars[i] == "[", chars[i - 1] == "[" { break }
            i -= 1
        }
        guard i > 0 else { return nil }
        let open = i - 1
        guard open == 0 || chars[open - 1] != "!" else { return nil }
        // The last line must be prose, and the brackets outside its code spans.
        let lineStart = (chars[..<open].lastIndex(of: "\n") ?? -1) + 1
        guard let last = BudLinks.prose(body).last, last.written == Array(chars[lineStart...]),
              last.blank[open - lineStart] == "[" else { return nil }
        query = String(chars[(open + 2)...])
        range = open..<chars.count
        guard query.count <= 80 else { return nil }
    }

    /// A title a link can carry as it is: `#`, `|` and brackets would cut it.
    public static func linkable(_ title: String) -> Bool {
        !title.contains { "#|[]".contains($0) }
    }

    /// The buds whose title holds the query, those it starts first, at most `limit`. A bud never
    /// links to itself, and a title a link cannot carry is left out.
    public func candidates(in tree: Tree, excluding id: UUID, limit: Int = 6) -> [Bud] {
        let q = BudLinks.fold(query.trimmingCharacters(in: .whitespaces))
        let found = tree.buds.filter {
            $0.id != id && Self.linkable($0.text) && (q.isEmpty || BudLinks.fold($0.text).contains(q))
        }
        return found
            .sorted { a, b in
                let (sa, sb) = (BudLinks.fold(a.text).hasPrefix(q), BudLinks.fold(b.text).hasPrefix(q))
                return sa != sb ? sa : a.text.localizedStandardCompare(b.text) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    /// What a link to `bud` says: its title, or its path when another bud has that title too.
    public static func target(for bud: Bud, in tree: Tree) -> String {
        tree.resolve(bud.text) == bud.id ? bud.text : tree.linkPath(of: bud.id)
    }

    /// `body` with the link being typed made a link to `target`; with a label, the query becomes it.
    public func complete(_ body: String, with target: String, labelled: Bool = false) -> String {
        var chars = Array(body)
        let label = query.trimmingCharacters(in: .whitespaces)
        let link = labelled && !label.isEmpty && label != target ? "[[\(target)|\(label)]]" : "[[\(target)]]"
        chars.replaceSubrange(range, with: Array(link))
        return String(chars)
    }

    /// Whether an edit from `old` to `new` was made at this link: it changed nothing before the
    /// open `[[`. Only then do the picker's keys stand in for the editor's.
    public func edited(from old: String, to new: String) -> Bool {
        let shared = zip(old, new).prefix { $0 == $1 }.count
        return shared >= range.lowerBound && old != new
    }
}

/// Every bud's title, as written and folded, so resolving a link reads no bud twice.
struct TitleIndex {
    var exact: [String: [UUID]] = [:]
    var folded: [String: [UUID]] = [:]

    init(_ tree: Tree) {
        for bud in tree.buds {
            exact[bud.text, default: []].append(bud.id)
            folded[BudLinks.fold(bud.text), default: []].append(bud.id)
        }
    }
}

/// Which buds link to which, read once from every body: what the canvas draws for the lit card
/// and counts on each card.
public struct LinkGraph: Equatable, Sendable {
    /// The buds each bud links to, once each, in the order its body names them.
    public var out: [UUID: [UUID]] = [:]
    /// The buds that link to each bud.
    public var into: [UUID: Set<UUID>] = [:]

    public init() {}

    public init(_ tree: Tree) {
        var resolved: [String: UUID?] = [:]
        let index = TitleIndex(tree)
        for bud in tree.buds where bud.body.contains("[[") {
            var seen: Set<UUID> = []
            for link in BudLinks.parse(bud.body) {
                let to: UUID?
                if let known = resolved[link.target] { to = known } else {
                    to = tree.resolve(link.target, in: index)
                    resolved[link.target] = to
                }
                guard let to, to != bud.id, seen.insert(to).inserted else { continue }
                out[bud.id, default: []].append(to)
                into[to, default: []].insert(bud.id)
            }
        }
    }

    /// Every bud linked with `id` either way, each with whether the link points away from it.
    public func around(_ id: UUID) -> [(other: UUID, outgoing: Bool)] {
        let away = out[id] ?? []
        let toward = (into[id] ?? []).subtracting(away).sorted { $0.uuidString < $1.uuidString }
        return away.map { ($0, true) } + toward.map { ($0, false) }
    }
}
