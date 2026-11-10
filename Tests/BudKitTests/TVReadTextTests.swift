import XCTest
@testable import BudKit

final class TVReadTextTests: XCTestCase {
    func testTheNextStepIsTheSoonestOpenToDoInside() throws {
        let tree = Tree.seed()
        let newsletter = try XCTUnwrap(tree.children(of: rootID).first)
        XCTAssertEqual(TVReadText.nextStep(in: tree, under: newsletter.id), "Next: Verify the address")
        XCTAssertEqual(TVReadText.playPauseHint(in: tree, under: newsletter.id), "Play/Pause closes Verify the address")
        let walk = try XCTUnwrap(tree.today().scheduled.first)
        XCTAssertNil(TVReadText.nextStep(in: tree, under: walk.id), "A leaf to-do is its own next step, so the line stays away")
        XCTAssertEqual(TVReadText.playPauseHint(in: tree, under: walk.id), "Play/Pause closes this to-do")
        let routines = try XCTUnwrap(tree.children(of: rootID).first { $0.text == "Routines" })
        XCTAssertNil(TVReadText.playPauseHint(in: tree, under: routines.id), "A note with nothing open inside has nothing to close")
    }

    func testTheInsideLineCountsChildrenAndOpenToDos() throws {
        let tree = Tree.seed()
        let newsletter = try XCTUnwrap(tree.children(of: rootID).first)
        XCTAssertEqual(TVReadText.insideLine(in: tree, under: newsletter.id), "5 inside · 3 open")
        XCTAssertGreaterThan(tree.openCount(under: newsletter.id), 2, "open counts the children only, not the to-dos below them")
        let routines = try XCTUnwrap(tree.children(of: rootID).first { $0.text == "Routines" })
        XCTAssertEqual(TVReadText.insideLine(in: tree, under: routines.id), "Nothing inside yet")
    }

    func testTheKindLineReadsKindDatesAndPin() {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        var bud = Bud(id: UUID(), text: "Pick a name", state: .open, parent: rootID, order: 1)
        XCTAssertEqual(TVReadText.kindLine(bud), "To-do")
        bud.due = day
        bud.pinned = true
        let line = TVReadText.kindLine(bud)
        XCTAssertTrue(line.hasPrefix("To-do · Due "), line)
        XCTAssertTrue(line.hasSuffix(" · Pinned"), line)
        bud.state = .done
        XCTAssertTrue(TVReadText.kindLine(bud).hasPrefix("Done · Due "))
        XCTAssertEqual(TVReadText.kindLine(Bud(id: UUID(), text: "Warm", state: nil, parent: rootID, order: 1)), "Note")
    }

    func testLinkedFromCountsTheBudsThatLinkHere() {
        let target = Bud(text: "Garden")
        let tree = Tree(buds: [target, Bud(text: "A", body: "See [[Garden]]."), Bud(text: "B", body: "[[garden|it]] and [[Garden]]")])
        XCTAssertEqual(TVReadText.linkedFromLine(count: tree.backlinks(to: target.id).count), "Linked from · 2")
        XCTAssertNil(TVReadText.linkedFromLine(count: Tree(buds: [target]).backlinks(to: target.id).count))
        XCTAssertEqual(BudLinks.shown("See [[Garden|the garden]] and `[[x]]`"), "See the garden and `[[x]]`")
    }
}
