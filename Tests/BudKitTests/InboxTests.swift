import XCTest
@testable import BudKit

final class InboxTests: XCTestCase {
    func testCaptureLandsUnderTheInboxAsANoteWithItsSource() throws {
        var t = Tree()
        let first = t.capture("Call about the venue", source: "mac")
        let second = t.capture("Buy seed packets", source: "iphone")
        XCTAssertEqual(first.parent, inboxID)
        XCTAssertNil(first.state, "A capture is a note until it is enriched")
        XCTAssertEqual(first.source, "mac")
        XCTAssertEqual(second.source, "iphone")
        XCTAssertGreaterThan(second.order, first.order, "Order after the last")
        XCTAssertEqual(t.inbox().map(\.text), ["Call about the venue", "Buy seed packets"])
        XCTAssertNotEqual(inboxID, rootID)
    }

    func testInboxBudsAreNotUnderTheRootOrInAnyLens() throws {
        var t = Tree.seed()
        let before = t.walk(under: rootID).map(\.id)
        let pinned = t.pinned().map(\.id)
        let openCount = t.openTodos().flatMap(\.todos).count
        let today = t.today()
        let todayCount = today.due.count + today.scheduled.count
        let captured = t.capture("Stray thought", source: "tv")
        t.setPinned(captured.id, true)
        t.setDue(captured.id, Date().addingTimeInterval(-86_400))
        XCTAssertEqual(t.walk(under: rootID).map(\.id), before)
        XCTAssertEqual(t.pinned().map(\.id), pinned)
        XCTAssertEqual(t.openTodos().flatMap(\.todos).count, openCount)
        let again = t.today()
        XCTAssertEqual(again.due.count + again.scheduled.count, todayCount)
        XCTAssertFalse(t.children(of: rootID).contains { $0.id == captured.id })
    }

    func testSearchFindsInboxBudsWithTheTrailInbox() throws {
        var t = Tree.seed()
        let captured = t.capture("Zebra idea", source: "ipad")
        let hits = TreeSearcher(tree: t).search("zebra")
        XCTAssertEqual(hits.map(\.id), [captured.id])
        XCTAssertEqual(hits.first?.trail, ["Inbox"])
        XCTAssertEqual(hits.first?.trailText, "Inbox")
    }

    func testMoveTargetsListEverythingAndEveryBudButNotTheBudsOwnBranch() throws {
        var t = Tree()
        let a = t.add("Alpha", todo: false, under: rootID)
        let b = t.add("Beta", todo: false, under: a.id)
        let c = t.add("Gamma", todo: false, under: rootID)
        let captured = t.capture("Captured", source: "mac")
        let all = MoveTargets(tree: t).matching("", for: captured.id)
        XCTAssertEqual(all.map(\.id), [rootID, a.id, b.id, c.id], "Everything first, the inbox is not a home")
        XCTAssertEqual(all.first?.title, "Everything")
        XCTAssertEqual(MoveTargets(tree: t).matching("  GAM ", for: captured.id).map(\.id), [c.id])
        XCTAssertEqual(MoveTargets(tree: t).matching("", for: a.id).map(\.id), [rootID, c.id], "Not itself or its branch")
        XCTAssertEqual(MoveTargets(tree: t).matching("every", for: a.id).map(\.id), [rootID])
    }

    func testMoveReparentsTheWholeBranchAfterTheLastChild() throws {
        var t = Tree()
        let thread = t.add("Thread", todo: false, under: rootID)
        let existing = t.add("Existing", todo: false, under: thread.id)
        let captured = t.capture("Captured", source: "mac")
        let child = t.add("Detail", todo: false, under: captured.id)
        XCTAssertTrue(t.move(captured.id, under: thread.id))
        XCTAssertEqual(t.bud(captured.id)?.parent, thread.id)
        XCTAssertEqual(t.children(of: thread.id).map(\.text), ["Existing", "Captured"])
        XCTAssertGreaterThan(try XCTUnwrap(t.bud(captured.id)).order, existing.order)
        XCTAssertEqual(t.bud(child.id)?.parent, captured.id, "The branch travels with it")
        XCTAssertTrue(t.inbox().isEmpty)
        XCTAssertEqual(t.walk(under: thread.id).map(\.text), ["Existing", "Captured", "Detail"])
    }

    func testMoveToTheRootIsAllowed() throws {
        var t = Tree()
        let captured = t.capture("Captured", source: "mac")
        XCTAssertTrue(t.move(captured.id, under: rootID))
        XCTAssertEqual(t.children(of: rootID).map(\.id), [captured.id])
    }

    func testMoveRefusesItselfAndItsOwnDescendants() throws {
        var t = Tree()
        let a = t.add("A", todo: false, under: rootID)
        let b = t.add("B", todo: false, under: a.id)
        let c = t.add("C", todo: false, under: b.id)
        let before = t
        XCTAssertFalse(t.move(a.id, under: a.id), "Under itself")
        XCTAssertFalse(t.move(a.id, under: b.id), "Under its child")
        XCTAssertFalse(t.move(a.id, under: c.id), "Under its descendant")
        XCTAssertEqual(t, before, "A refused move changes nothing")
    }

    func testMoveRefusesAnUnknownBudOrParent() throws {
        var t = Tree()
        let a = t.add("A", todo: false, under: rootID)
        let before = t
        XCTAssertFalse(t.move(UUID(), under: rootID))
        XCTAssertFalse(t.move(a.id, under: UUID()))
        XCTAssertFalse(t.move(rootID, under: a.id))
        XCTAssertEqual(t, before)
    }

    func testOldFilesDecodeWithoutASource() throws {
        let json = """
        {"buds":[{"id":"11111111-1111-1111-1111-111111111111","text":"Old bud","parent":"00000000-0000-0000-0000-000000000000","order":1}]}
        """
        let t = try JSONDecoder().decode(Tree.self, from: Data(json.utf8))
        XCTAssertNil(t.buds.first?.source)
        let captured = Tree().capturing("Fresh", source: "mac")
        let data = try JSONEncoder().encode(captured)
        let again = try JSONDecoder().decode(Tree.self, from: data)
        XCTAssertEqual(again.inbox().first?.source, "mac", "The source survives a save")
    }

    func testTheSeedHoldsTwoCapturesFromTheMac() throws {
        let t = Tree.seed()
        let inbox = t.inbox()
        XCTAssertEqual(inbox.count, 2)
        XCTAssertTrue(inbox.allSatisfy { $0.source == "mac" && $0.parent == inboxID && !$0.isTodo })
    }
}

private extension Tree {
    func capturing(_ line: String, source: String) -> Tree {
        var copy = self
        copy.capture(line, source: source)
        return copy
    }
}
