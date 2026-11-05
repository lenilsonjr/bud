import XCTest
@testable import BudKit

final class RootTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }
    private func ids(_ items: [SourceItem], _ kind: SourceKind) -> [String] {
        Root.order(items, kind: kind, now: now).map(\.id)
    }

    func testMailPutsTheNewestUnreadNearestTheSoil() {
        let items = [
            SourceItem(id: "read-new", title: "a", date: at(-1)),
            SourceItem(id: "unread-old", title: "b", date: at(-90), unread: true),
            SourceItem(id: "unread-new", title: "c", date: at(-5), unread: true),
            SourceItem(id: "read-old", title: "d", date: at(-300)),
        ]
        XCTAssertEqual(ids(items, .mail), ["unread-new", "unread-old", "read-new", "read-old"])
    }

    func testCalendarPutsTheNextEventFirstAndWhatHasPassedLast() {
        let items = [
            SourceItem(id: "tomorrow", title: "a", date: at(24 * 60)),
            SourceItem(id: "earlier", title: "b", date: at(-120)),
            SourceItem(id: "soon", title: "c", date: at(30)),
            SourceItem(id: "just-now", title: "d", date: at(-10)),
        ]
        XCTAssertEqual(ids(items, .calendar), ["soon", "tomorrow", "just-now", "earlier"])
    }

    func testGitHubPutsReviewRequestsThenAssignedIssuesThenMyPullRequests() {
        let items = [
            SourceItem(id: "mine", title: "a", date: at(-1), role: .mine),
            SourceItem(id: "assigned", title: "b", date: at(-2), role: .assigned),
            SourceItem(id: "review-old", title: "c", date: at(-60), role: .reviewRequest),
            SourceItem(id: "review-new", title: "d", date: at(-3), role: .reviewRequest),
        ]
        XCTAssertEqual(ids(items, .github), ["review-new", "review-old", "assigned", "mine"])
    }

    func testLinearPutsTheDueDateFirstThenThePriority() {
        let items = [
            SourceItem(id: "undated-none", title: "a", priority: 0),
            SourceItem(id: "undated-low", title: "b", priority: 4),
            SourceItem(id: "undated-urgent", title: "c", priority: 1),
            SourceItem(id: "due-later", title: "d", date: at(48 * 60), priority: 4),
            SourceItem(id: "due-soon", title: "e", date: at(60), priority: 3),
        ]
        XCTAssertEqual(ids(items, .linear), ["due-soon", "due-later", "undated-urgent", "undated-low", "undated-none"])
    }

    func testARootShowsThreeItemsAndCountsTheRestBelow() {
        let items = (1...9).map { SourceItem(id: "M-\($0)", title: "Mail \($0)", date: at(Double(-$0))) }
        let root = Root(SourceAccount(id: "a", kind: .mail, items: items), now: now)
        XCTAssertEqual(root.items.map(\.id), ["M-1", "M-2", "M-3"])
        XCTAssertEqual(root.more, 6)
        XCTAssertEqual(root.count, 9)
    }

    func testAShortRootHasNoMoreRow() {
        let root = Root(SourceAccount(id: "a", kind: .mail, items: [SourceItem(id: "M-1", title: "x")]), now: now)
        XCTAssertEqual(root.more, 0)
    }

    func testTheLeafDotShowsWhenTheItemUnderTheSoilNeedsYou() {
        let unread = SourceAccount(id: "a", kind: .mail, items: [SourceItem(id: "1", title: "x", unread: true)])
        let read = SourceAccount(id: "b", kind: .mail, items: [SourceItem(id: "1", title: "x")])
        let soon = SourceAccount(id: "c", kind: .calendar, items: [SourceItem(id: "1", title: "x", date: at(40))])
        let later = SourceAccount(id: "d", kind: .calendar, items: [SourceItem(id: "1", title: "x", date: at(240))])
        XCTAssertTrue(Root(unread, now: now).leaf)
        XCTAssertFalse(Root(read, now: now).leaf)
        XCTAssertTrue(Root(soon, now: now).leaf)
        XCTAssertFalse(Root(later, now: now).leaf)
        XCTAssertFalse(Root(SourceAccount(id: "e", kind: .github), now: now).leaf)
    }

    func testALockedRootShowsNothing() {
        let items = [SourceItem(id: "1", title: "x", unread: true)]
        let root = Root(SourceAccount(id: "a", kind: .mail, locked: true, items: items), now: now)
        XCTAssertEqual(root.items, [])
        XCTAssertEqual(root.count, 0)
        XCTAssertFalse(root.leaf)
    }

    func testTheFromKeyStartsWithTheKind() {
        XCTAssertEqual(SourceKind.mail.key("M-1"), "mail:M-1")
        XCTAssertEqual(SourceKind.calendar.key("E-2"), "calendar:E-2")
    }

    func testTheSamplesAreReadyForPictures() {
        let roots = SourceAccount.samples(now: now).map { Root($0, now: now) }
        XCTAssertEqual(roots.map(\.account.kind), [.mail, .calendar, .github, .linear])
        XCTAssertEqual(roots[0].more, 2)
        XCTAssertTrue(roots[2].account.locked)
    }

    func testPlantingInTheTreeCarriesTheKeyAndIsFoundAgain() {
        var tree = Tree.seed()
        let bud = tree.plant("Lease renewal draft", todo: true, under: inboxID, from: "mail:M-102")
        XCTAssertEqual(tree.bud(bud.id)?.from, "mail:M-102")
        XCTAssertEqual(tree.bud(bud.id)?.parent, inboxID)
        XCTAssertTrue(tree.bud(bud.id)?.isTodo ?? false)
        XCTAssertEqual(tree.planted(from: "mail:M-102")?.id, bud.id)
        tree.trash(bud.id)
        XCTAssertNil(tree.planted(from: "mail:M-102"), "a bud in the Trash is not found")
    }
}
