import XCTest
@testable import BudKit

final class LiveRulesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var stamp: String { ISO8601DateFormatter().string(from: now) }
    private func bud(_ text: String, fromState: String? = nil) -> Bud { Bud(text: text, from: "calendar:E-1", fromState: fromState) }
    private func event(_ title: String, at minutes: Double, cancelled: Bool = false) -> SourceItem {
        SourceItem(id: "E-1", title: title, date: Date(timeIntervalSince1970: 1_800_000_000 + minutes * 60), cancelled: cancelled)
    }

    func testTheFirstSightIsRememberedAndChangesNothing() {
        let result = LiveRules.changes(for: bud("Flight"), kind: .calendar, sighting: .seen(event("Flight", at: 60)), last: nil, now: now)
        XCTAssertEqual(result.changes, [])
        XCTAssertEqual(result.seen?.title, "Flight")
    }

    func testAMovedEventMovesTheBudAndSaysSo() {
        let last = SourceSnapshot(event("Flight", at: 60))
        let result = LiveRules.changes(for: bud("Flight"), kind: .calendar, sighting: .seen(event("Flight", at: 180)), last: last, now: now)
        XCTAssertEqual(result.changes, [.when(Date(timeIntervalSince1970: 1_800_000_000 + 180 * 60)), .mark("moved \(stamp)")])
    }

    func testALocalEditStandsUntilTheSourceChangesAgain() {
        let last = SourceSnapshot(event("Flight", at: 60))
        let same = LiveRules.changes(for: bud("Flight to Lisbon, window seat"), kind: .calendar, sighting: .seen(event("Flight", at: 60)), last: last, now: now)
        XCTAssertEqual(same.changes, [])
        let renamed = LiveRules.changes(for: bud("Flight to Lisbon, window seat"), kind: .calendar, sighting: .seen(event("Flight TP 1350", at: 60)), last: last, now: now)
        XCTAssertEqual(renamed.changes, [.rename("Flight TP 1350"), .mark("renamed \(stamp)")])
    }

    func testACancelledEventIsMarkedAndUnmarkedWhenItComesBack() {
        let last = SourceSnapshot(event("Viewing", at: 60))
        let cancelled = LiveRules.changes(for: bud("Viewing"), kind: .calendar, sighting: .seen(event("Viewing", at: 60, cancelled: true)), last: last, now: now)
        XCTAssertEqual(cancelled.changes, [.mark("cancelled")])
        let back = LiveRules.changes(
            for: bud("Viewing", fromState: "cancelled"), kind: .calendar, sighting: .seen(event("Viewing", at: 60)),
            last: cancelled.seen, now: now)
        XCTAssertEqual(back.changes, [.mark(nil)])
    }

    func testAGoneItemIsMarkedOnceAndKeepsItsValues() {
        let last = SourceSnapshot(event("Viewing", at: 60))
        let gone = LiveRules.changes(for: bud("Viewing"), kind: .calendar, sighting: .gone, last: last, now: now)
        XCTAssertEqual(gone.changes, [.mark("gone")])
        XCTAssertEqual(gone.seen, last)
        let again = LiveRules.changes(for: bud("Viewing", fromState: "gone"), kind: .calendar, sighting: .gone, last: last, now: now)
        XCTAssertEqual(again.changes, [])
    }

    func testMailFlagsOpenAndCloseTheToDo() {
        let mail = Bud(text: "Lease draft", from: "mail:M-1")
        let unflagged = SourceItem(id: "M-1", title: "Lease draft")
        let flagged = SourceItem(id: "M-1", title: "Lease draft", todo: true)
        XCTAssertEqual(LiveRules.changes(for: mail, kind: .mail, sighting: .seen(flagged), last: SourceSnapshot(unflagged), now: now).changes, [.state(.open)])
        XCTAssertEqual(LiveRules.changes(for: mail, kind: .mail, sighting: .seen(unflagged), last: SourceSnapshot(flagged), now: now).changes, [.state(.done)])
    }

    func testTheFromStateReadsBackAsAMark() {
        XCTAssertEqual(SourceMark(fromState: "cancelled")?.status, .cancelled)
        XCTAssertEqual(SourceMark(fromState: "gone")?.status, .gone)
        let moved = SourceMark(fromState: "moved \(stamp)")
        XCTAssertEqual(moved?.status, .changed("moved"))
        XCTAssertEqual(moved?.at, now)
        XCTAssertNil(SourceMark(fromState: nil))
        XCTAssertNil(SourceMark(fromState: " "))
    }
}
