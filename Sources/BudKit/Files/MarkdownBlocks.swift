import Foundation

/// The body split into the blocks a page is made of: headings, bullets, paragraphs. A small
/// line pass, enough for the notes people write; inline marks (bold, links) stay in the text
/// for the inline renderer. Nothing it cannot read is lost: an odd line is a paragraph.
public enum MarkdownBlocks {
    public enum Block: Equatable, Sendable {
        case heading(level: Int, text: String)
        case bullets([String])
        case paragraph(String)
    }

    public static func parse(_ source: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var bullets: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        func flushBullets() {
            if !bullets.isEmpty { blocks.append(.bullets(bullets)) }
            bullets = []
        }

        for raw in source.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph(); flushBullets()
                continue
            }
            if let (level, text) = heading(line) {
                flushParagraph(); flushBullets()
                blocks.append(.heading(level: level, text: text))
                continue
            }
            if let item = bullet(line) {
                flushParagraph()
                bullets.append(item)
                continue
            }
            flushBullets()
            paragraph.append(line)
        }
        flushParagraph(); flushBullets()
        return blocks
    }

    private static func heading(_ line: String) -> (Int, String)? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count), line.dropFirst(hashes.count).first == " " else { return nil }
        let text = line.dropFirst(hashes.count + 1).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (hashes.count, text)
    }

    private static func bullet(_ line: String) -> String? {
        for mark in ["- ", "* ", "+ "] where line.hasPrefix(mark) {
            return String(line.dropFirst(mark.count)).trimmingCharacters(in: .whitespaces)
        }
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
            return String(line.dropFirst(digits.count + 2)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Inline marks read: bold, italics, code, links. Source the reader cannot parse comes back
    /// as it was written, never as nothing.
    public static func inline(_ text: String) -> AttributedString {
        #if canImport(Darwin)
        let parsed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        return parsed ?? AttributedString(text)
        #else
        return AttributedString(text)
        #endif
    }
}
