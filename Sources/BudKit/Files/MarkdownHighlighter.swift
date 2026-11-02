import Foundation

/// A light pass over Markdown source: it finds headings, bullets, bold runs and links so the
/// editor can colour them. A regex pass, not a parser; nothing is rewritten.
public enum MarkdownHighlighter {
    public enum Kind: Equatable, Sendable {
        case heading, bullet, bold, link
    }

    public struct Span: Equatable, Sendable {
        public let range: Range<Int>
        public let kind: Kind
    }

    private static let patterns: [(Kind, NSRegularExpression)] = [
        (.heading, try! NSRegularExpression(pattern: "^#{1,6} .*$", options: [.anchorsMatchLines])),
        (.bullet, try! NSRegularExpression(pattern: "^\\s*(?:[-*+]|\\d+\\.) ", options: [.anchorsMatchLines])),
        (.bold, try! NSRegularExpression(pattern: "\\*\\*[^*\\n]+\\*\\*")),
        (.link, try! NSRegularExpression(pattern: "\\[[^\\]\\n]+\\]\\([^)\\s]+\\)|\\[\\[[^\\]\\n]+\\]\\]")),
    ]

    /// Every span in the text, as UTF-16 offsets, in document order.
    public static func spans(in text: String) -> [Span] {
        let whole = NSRange(location: 0, length: (text as NSString).length)
        var found: [Span] = []
        for (kind, regex) in patterns {
            for match in regex.matches(in: text, range: whole) {
                found.append(Span(range: match.range.location..<(match.range.location + match.range.length), kind: kind))
            }
        }
        return found.sorted { ($0.range.lowerBound, $0.range.upperBound) < ($1.range.lowerBound, $1.range.upperBound) }
    }
}
