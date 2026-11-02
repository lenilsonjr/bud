import XCTest
@testable import BudKit

final class MarkdownBlocksTests: XCTestCase {
    func testHeadingsBulletsAndParagraphsComeApart() {
        let source = "# First issue\n\nOne story, **one tip**, one date.\nSecond line of the same paragraph.\n\n- a link to [the club](https://example.org)\n- another\n\n2. numbered\n\n## Later"
        XCTAssertEqual(MarkdownBlocks.parse(source), [
            .heading(level: 1, text: "First issue"),
            .paragraph("One story, **one tip**, one date. Second line of the same paragraph."),
            .bullets(["a link to [the club](https://example.org)", "another"]),
            .bullets(["numbered"]),
            .heading(level: 2, text: "Later"),
        ])
    }

    func testOddLinesAreParagraphsNotNothing() {
        XCTAssertEqual(MarkdownBlocks.parse("#nospace\n####### seven\n-dash"), [.paragraph("#nospace ####### seven -dash")])
        XCTAssertEqual(MarkdownBlocks.parse(""), [])
        XCTAssertEqual(MarkdownBlocks.parse("\n\n  \n"), [])
    }

    func testBrokenInlineMarkdownFallsBackToThePlainText() {
        let broken = "a broken [link](https://example.org"
        XCTAssertEqual(String(MarkdownBlocks.inline(broken).characters), broken)
        XCTAssertFalse(MarkdownBlocks.inline("**bold**").characters.isEmpty)
    }
}
