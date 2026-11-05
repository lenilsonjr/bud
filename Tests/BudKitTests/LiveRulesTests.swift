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
        XCTAssertEqual(LiveRules.changes(for: mail, kind: .mail, sighting: .seen(flagged), last: SourceSnapshot(unflagged), now: now).changes, [.state(.open), .mark("flagged \(stamp)")])
        XCTAssertEqual(LiveRules.changes(for: mail, kind: .mail, sighting: .seen(unflagged), last: SourceSnapshot(flagged), now: now).changes, [.state(.done), .mark("unflagged \(stamp)")])
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

final class LiveRulesCatchUpTests: XCTestCase {
    func testADeviceThatLookedBeforeAnotherOneChangedTheBudCatchesUpWithoutWriting() {
        let then = Date(timeIntervalSince1970: 1_800_000_000)
        let later = then.addingTimeInterval(3600)
        let last = SourceSnapshot(SourceItem(id: "E-1", title: "A"), at: then)
        let stamp = ISO8601DateFormatter().string(from: then.addingTimeInterval(600))
        let bud = Bud(text: "My B", from: "calendar:E-1", fromState: "renamed \(stamp)")
        let result = LiveRules.changes(for: bud, kind: .calendar, sighting: .seen(SourceItem(id: "E-1", title: "B")), last: last, now: later)
        XCTAssertEqual(result.changes, [], "the edit made after the other device renamed it stands")
        XCTAssertEqual(result.seen?.title, "B")
    }

    func testAnAlarmInsideAnEventDoesNotTakeItsUidOrTitle() {
        let text = "BEGIN:VEVENT\nUID:event\nSUMMARY:Dentist\nBEGIN:VALARM\nUID:alarm\nSUMMARY:Reminder\nEND:VALARM\nDTSTART:20261106T090000Z\nEND:VEVENT"
        let events = ICS.events(in: text)
        XCTAssertEqual(events.map(\.uid), ["event"])
        XCTAssertEqual(events.first?.summary, "Dentist")
        XCTAssertNotNil(events.first?.start)
    }

    func testAPropertyTheServerDoesNotHaveIsLeftOut() {
        let xml = """
        <d:multistatus xmlns:d="DAV:"><d:response><d:href>/c/</d:href>
        <d:propstat><d:prop><cs:getctag xmlns:cs="http://calendarserver.org/ns/">42</cs:getctag></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
        <d:propstat><d:prop><d:sync-token/></d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat>
        </d:response></d:multistatus>
        """
        let tree = XMLNode.parse(Data(xml.utf8))!
        tree.dropMissing()
        XCTAssertNil(tree.first("sync-token"))
        XCTAssertEqual(tree.first("getctag")?.text, "42")
    }
}
