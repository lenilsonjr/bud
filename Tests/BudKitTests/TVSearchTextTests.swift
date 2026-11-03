import XCTest
@testable import BudKit

final class TVSearchTextTests: XCTestCase {
    func testTheHeadingCountsTheHits() {
        XCTAssertEqual(TVSearchText.heading(query: "", hits: 8), "Recent")
        XCTAssertEqual(TVSearchText.heading(query: "  ", hits: 8), "Recent")
        XCTAssertEqual(TVSearchText.heading(query: "name", hits: 0), "No match")
        XCTAssertEqual(TVSearchText.heading(query: "name", hits: 1), "1 match")
        XCTAssertEqual(TVSearchText.heading(query: "the", hits: 7), "7 matches")
        XCTAssertEqual(TVSearchText.empty(query: " zebra "), "Nothing is called “zebra”. Try a shorter word.")
    }

    func testAHitBecomesARowWithItsTrail() throws {
        let tree = Tree.seed()
        let hit = try XCTUnwrap(TreeSearcher(tree: tree).search("verify").first)
        let row = try XCTUnwrap(TVFilesText.row(hit.id, in: tree))
        XCTAssertEqual(row.title, "Verify the address")
        XCTAssertEqual(row.caption, "Launch the newsletter › Set up the sender")
        XCTAssertNil(TVFilesText.row(UUID(), in: tree))
    }

    func testTheSettingsWordsNameTheDevice() {
        XCTAssertTrue(TVSettingsText.startOverTitle.contains("Apple TV"))
        XCTAssertTrue(TVSettingsText.startOverCaption.contains("Apple TV"))
    }
}
