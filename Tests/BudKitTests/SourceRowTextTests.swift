import XCTest
@testable import BudKit

final class SourceRowTextTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

    func testTheCardRowHasFourStates() {
        XCTAssertEqual(SourceRowText.card(from: "linear:PRJ-7", mark: nil, now: now), "Linear · live")
        XCTAssertEqual(SourceRowText.card(from: "calendar:E-1", mark: SourceMark(status: .changed("moved"), at: ago(60)), now: now), "moved 1h ago")
        XCTAssertEqual(SourceRowText.card(from: "calendar:E-1", mark: SourceMark(status: .cancelled), now: now), "cancelled at source")
        XCTAssertEqual(SourceRowText.card(from: "github:42", mark: SourceMark(status: .closed), now: now), "closed at source")
        XCTAssertEqual(SourceRowText.card(from: "mail:M-1", mark: SourceMark(status: .gone), now: now), "gone from source")
    }

    func testAChangeShowsForADayThenTheRowIsLiveAgain() {
        let fresh = SourceMark(status: .changed("renamed"), at: ago(23 * 60))
        let stale = SourceMark(status: .changed("renamed"), at: ago(25 * 60))
        XCTAssertEqual(SourceRowText.card(from: "mail:M-1", mark: fresh, now: now), "renamed 23h ago")
        XCTAssertEqual(SourceRowText.card(from: "mail:M-1", mark: stale, now: now), "Mail · live")
    }

    func testThePageNamesTheSourceTheItemAndTheLastSync() {
        XCTAssertEqual(SourceRowText.title(from: "linear:PRJ-77"), "From Linear · PRJ-77")
        XCTAssertEqual(SourceRowText.synced(SourceMark(synced: ago(5), device: "Mac"), now: now), "Synced 5 min ago on Mac")
        XCTAssertEqual(SourceRowText.synced(SourceMark(synced: ago(0.2)), now: now), "Synced just now")
        XCTAssertEqual(SourceRowText.synced(nil, now: now), "Not synced yet")
        XCTAssertEqual(SourceRowText.open(from: "github:42"), "Open in GitHub")
    }

    func testEachSourceMarksTheFieldsItOwns() {
        XCTAssertTrue(SourceRowText.owns(.title, from: "calendar:E-1"))
        XCTAssertTrue(SourceRowText.owns(.when, from: "calendar:E-1"))
        XCTAssertFalse(SourceRowText.owns(.state, from: "calendar:E-1"))
        XCTAssertTrue(SourceRowText.owns(.due, from: "linear:PRJ-1"))
        XCTAssertTrue(SourceRowText.owns(.state, from: "linear:PRJ-1"))
        XCTAssertFalse(SourceRowText.owns(.due, from: "mail:M-1"))
        XCTAssertFalse(SourceRowText.owns(.title, from: "elsewhere:1"))
    }

    func testAnUnknownKindKeepsItsPrefix() {
        XCTAssertEqual(SourceRowText.card(from: "notes:9", mark: nil, now: now), "notes · live")
        XCTAssertEqual(SourceRowText.origin("mail:M:1").id, "M:1")
    }
}
