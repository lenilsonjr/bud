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

    /// The links in a body, in order.
    public static func parse(_ body: String) -> [Written] {
        prose(body).flatMap { links(in: $0).map(\.link) }
    }

    /// The lines of a body outside fenced code, code spans blanked out.
    static func prose(_ body: String) -> [String] {
        var fenced = false
        var out: [String] = []
        for line in body.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                fenced.toggle()
                continue
            }
            if !fenced { out.append(blankingCode(line)) }
        }
        return out
    }

    private static func blankingCode(_ line: String) -> String {
        var out = ""
        var inCode = false
        for c in line {
            if c == "`" { inCode.toggle(); out.append(c) } else { out.append(inCode ? " " : c) }
        }
        return out
    }

    /// Each link in one line with the range it takes, brackets included.
    static func links(in line: String) -> [(link: Written, range: Range<String.Index>)] {
        var out: [(Written, Range<String.Index>)] = []
        var i = line.startIndex
        while let open = line.range(of: "[[", range: i..<line.endIndex) {
            guard let close = line.range(of: "]]", range: open.upperBound..<line.endIndex) else { break }
            let inner = line[open.upperBound..<close.lowerBound]
            if inner.contains("[") || inner.contains("]") {
                i = line.index(after: open.lowerBound)
                continue
            }
            let embed = open.lowerBound > line.startIndex && line[line.index(before: open.lowerBound)] == "!"
            if !embed, let link = split(inner) { out.append((link, open.lowerBound..<close.upperBound)) }
            i = close.upperBound
        }
        return out
    }

    private static func split(_ inner: Substring) -> Written? {
        let parts = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let label = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        let target = (parts[0].split(separator: "#", omittingEmptySubsequences: false).first ?? "")
            .trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return nil }
        return Written(target: target, label: label.isEmpty ? nil : label)
    }
}

/// A bud that links to another, with the sentence the first such link sits in, links shown as
/// their text.
public struct Backlink: Equatable, Sendable, Identifiable {
    public var from: UUID
    public var sentence: String
    /// The link's text as it reads in the sentence.
    public var shown: String
    public var id: UUID { from }
}

extension Tree {
    /// The bud a link's target names: the one bud with that title, then the one with that title
    /// in any case. More than one at the first rank that has any, or none, is no bud.
    public func resolve(_ target: String) -> UUID? {
        let exact = buds.filter { $0.text == target }
        if !exact.isEmpty { return exact.count == 1 ? exact[0].id : nil }
        let folded = buds.filter { $0.text.caseInsensitiveCompare(target) == .orderedSame }
        return folded.count == 1 ? folded[0].id : nil
    }

    /// The buds that link to `id` in their body, one row each, in the order of the tree.
    public func backlinks(to id: UUID) -> [Backlink] {
        var out: [Backlink] = []
        for bud in buds where bud.id != id && bud.body.contains("[[") {
            found: for line in BudLinks.prose(bud.body) {
                for (link, range) in BudLinks.links(in: line) where resolve(link.target) == id {
                    out.append(Backlink(from: bud.id, sentence: Self.sentence(around: range, in: line), shown: link.shown))
                    break found
                }
            }
        }
        return out
    }

    /// The sentence of `line` that holds `range`, its links shown as their text and its list or
    /// heading mark left off.
    static func sentence(around range: Range<String.Index>, in line: String) -> String {
        let ends: Set<Character> = [".", "!", "?"]
        var start = range.lowerBound
        while start > line.startIndex {
            let before = line.index(before: start)
            if ends.contains(line[before]), start == line.endIndex || line[start].isWhitespace { break }
            start = before
        }
        var end = range.upperBound
        while end < line.endIndex {
            let next = line.index(after: end)
            if ends.contains(line[end]), next == line.endIndex || line[next].isWhitespace { end = next; break }
            end = next
        }
        var text = String(line[start..<end])
        for (link, linkRange) in BudLinks.links(in: text).reversed() { text.replaceSubrange(linkRange, with: link.shown) }
        text = text.trimmingCharacters(in: .whitespaces)
        for mark in ["- ", "* ", "+ "] where text.hasPrefix(mark) { text.removeFirst(mark.count) }
        while text.hasPrefix("#") { text.removeFirst() }
        return text.trimmingCharacters(in: .whitespaces)
    }
}
