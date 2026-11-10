import XCTest
@testable import BudKit

/// What a drop on each column writes, the tree applying it, and the words around it.
final class BoardDropTests: XCTestCase {
    private let columns = ["researching", "waiting", "doing"]

    private func bud(tags: [String] = [], state: BudState? = .open, fromState: String? = nil, body: String = "") -> Bud {
        Bud(text: "Pick the paper", state: state, body: body, fromState: fromState, tags: tags)
    }

    func testATagColumnSetsItsTagAndTakesTheOtherColumnTagsOut() throws {
        let drop = try XCTUnwrap(BoardDrop.of(bud(tags: ["waiting", "lawyer", "Doing"]), on: .tag("researching"), columns: columns))
        XCTAssertEqual(drop, BoardDrop(removed: ["waiting", "Doing"], added: "researching"))
        var tree = Tree()
        let planted = tree.add("Pick the paper", todo: true, under: rootID)
        tree.addTag(planted.id, "waiting")
        tree.addTag(planted.id, "lawyer")
        tree.addTag(planted.id, "Doing")
        tree.apply(drop, to: planted.id)
        XCTAssertEqual(tree.bud(planted.id)?.tags, ["lawyer", "researching"], "the tag that has no column stays")
        XCTAssertEqual(tree.bud(planted.id)?.state, .open)
    }

    func testACardCarryingTheColumnTagInItsBodyIsNotTaggedTwice() throws {
        let drop = try XCTUnwrap(BoardDrop.of(bud(tags: ["waiting"], body: "Still #doing it"), on: .tag("doing"), columns: columns))
        XCTAssertEqual(drop, BoardDrop(removed: ["waiting"]))
    }

    func testDoneClosesAndCancelledClosesWithTheMark() throws {
        XCTAssertEqual(BoardDrop.of(bud(tags: ["doing"]), on: .done, columns: columns), BoardDrop(state: .done), "the tags stay")
        XCTAssertEqual(BoardDrop.of(bud(state: nil), on: .done, columns: columns), BoardDrop(state: .done), "a note becomes a done to-do")
        XCTAssertEqual(BoardDrop.of(bud(), on: .cancelled, columns: columns), BoardDrop(state: .done, cancelled: true))
        XCTAssertEqual(BoardDrop.of(bud(state: .done), on: .cancelled, columns: columns), BoardDrop(cancelled: true))
        XCTAssertEqual(BoardDrop.of(bud(state: .done, fromState: "cancelled"), on: .done, columns: columns), BoardDrop(cancelled: false))
        var tree = Tree()
        let planted = tree.add("Pick the paper", todo: true, under: rootID)
        tree.apply(BoardDrop(state: .done, cancelled: true), to: planted.id)
        XCTAssertEqual(tree.bud(planted.id)?.state, .done)
        XCTAssertEqual(tree.bud(planted.id)?.isCancelled, true)
    }

    func testOpenTakesTheColumnTagsOutAndReopens() throws {
        XCTAssertEqual(
            BoardDrop.of(bud(tags: ["doing", "lawyer"], state: .done, fromState: "cancelled"), on: .open, columns: columns),
            BoardDrop(removed: ["doing"], state: .open, cancelled: false)
        )
        XCTAssertEqual(
            BoardDrop.of(bud(from: "mail:M1", fromState: "moved 2026-11-05T21:00:00Z"), on: .open, columns: columns), nil,
            "a planted bud's other marks are not a column"
        )
    }

    func testTheColumnTheCardSitsInIsNoDrop() {
        XCTAssertNil(BoardDrop.of(bud(tags: ["lawyer"]), on: .open, columns: columns))
        XCTAssertNil(BoardDrop.of(bud(tags: ["doing"]), on: .tag("doing"), columns: columns))
        XCTAssertNil(BoardDrop.of(bud(state: .done), on: .done, columns: columns))
        XCTAssertNil(BoardDrop.of(bud(state: .done, fromState: "cancelled"), on: .cancelled, columns: columns))
        XCTAssertTrue(BoardDrop().isEmpty)
    }

    func testUndoPutsTheFrontMatterBackAndKeepsWhatChangedSince() {
        var tree = Tree()
        let planted = tree.add("Pick the paper", todo: true, under: rootID)
        tree.addTag(planted.id, "doing")
        tree.addTag(planted.id, "lawyer")
        let before = tree.bud(planted.id)!
        let drop = BoardDrop(removed: ["doing"], added: "waiting", state: .done, cancelled: true)
        tree.apply(drop, to: planted.id)
        XCTAssertEqual(tree.bud(planted.id)?.tags, ["lawyer", "waiting"])
        tree.undo(drop, on: planted.id, before: before)
        XCTAssertEqual(tree.bud(planted.id), before, "doing is back in its old place")

        tree.apply(drop, to: planted.id)
        tree.addTag(planted.id, "printer")
        tree.undo(drop, on: planted.id, before: before)
        XCTAssertEqual(tree.bud(planted.id)?.tags, ["doing", "lawyer", "printer"], "the tag added since stays")
        XCTAssertEqual(tree.bud(planted.id)?.state, .open)
        XCTAssertNil(tree.bud(planted.id)?.fromState)
    }

    func testAPlantedBudsCancelledMarkIsItsSourcesToSet() {
        let planted = bud(from: "mail:M1", fromState: "moved 2026-11-05T21:00:00Z")
        XCTAssertEqual(
            BoardDrop.refusal(of: planted, on: .cancelled, columns: columns),
            "Pick the paper follows its source: cancelled is its source's to set"
        )
        XCTAssertNotNil(BoardDrop.refusal(of: bud(from: "mail:M1", fromState: "cancelled"), on: .open, columns: columns))
        XCTAssertNil(BoardDrop.refusal(of: planted, on: .done, columns: columns), "closing is the person's")
        XCTAssertNil(BoardDrop.refusal(of: bud(), on: .cancelled, columns: columns), "a bud made here can be cancelled")
    }

    func testABodyTagKeepsTheCardInItsColumnSoTheDropIsRefused() {
        let card = bud(tags: ["researching"], body: "Still #waiting on the lawyer")
        XCTAssertEqual(BoardDrop.column(of: card, columns: columns), .tag("researching"))
        XCTAssertEqual(
            BoardDrop.refusal(of: card, on: .tag("doing"), columns: columns),
            "Pick the paper stays in #waiting: its text says #waiting"
        )
        XCTAssertNil(BoardDrop.refusal(of: card, on: .tag("waiting"), columns: columns), "the body's column takes it")
        XCTAssertNil(BoardDrop.refusal(of: card, on: .done, columns: columns), "Done beats any tag")
        XCTAssertNotNil(BoardDrop.refusal(of: card, on: .open, columns: columns))
    }

    func testTheColumnRuleAgreesWithTheBoard() {
        var tree = Tree.seed(now: Date(timeIntervalSince1970: 1_794_000_000))
        let newsletter = tree.children(of: rootID).first { $0.text == "Launch the newsletter" }!
        let kids = tree.children(of: newsletter.id)
        tree.addTag(kids[0].id, "researching")
        tree.setBody(kids[0].id, "and #doing")
        tree.addTag(kids[1].id, "doing")
        tree.toggle(kids[2].id)
        tree.addTag(kids[2].id, "doing")
        let gone = tree.add("Printer quote", todo: true, under: kids[2].id)
        tree.buds[tree.buds.firstIndex { $0.id == gone.id }!].fromState = "cancelled"
        let board = Board(tree: tree, center: newsletter.id)
        for bud in tree.walk(under: newsletter.id) {
            let column = board.columns.first { $0.cards.contains { $0.id == bud.id } }?.kind
                ?? (board.cancelled.cards.contains { $0.id == bud.id } ? .cancelled : nil)
            XCTAssertEqual(BoardDrop.column(of: bud, columns: board.columnTags), column, bud.text)
        }
    }

    func testTheHintAndTheToastReadTheColumn() {
        XCTAssertEqual(BoardDrop.hint(on: .done), "Drop to close it")
        XCTAssertEqual(BoardDrop.hint(on: .cancelled), "Drop to cancel it")
        XCTAssertEqual(BoardDrop.hint(on: .open), "Drop to open it")
        XCTAssertEqual(BoardDrop.hint(on: .tag("doing")), "Drop to tag it #doing")
        XCTAssertEqual(BoardDrop.message(on: .done, title: "Pick the paper"), "Closed Pick the paper")
        XCTAssertEqual(BoardDrop.message(on: .cancelled, title: "Pick the paper"), "Cancelled Pick the paper")
        XCTAssertEqual(BoardDrop.message(on: .open, title: "Pick the paper"), "Moved Pick the paper to Open")
        XCTAssertEqual(BoardDrop.message(on: .tag("waiting"), title: "Pick the paper"), "Tagged Pick the paper #waiting")
        XCTAssertEqual(BoardDrop.failure(on: .done, title: "Pick the paper"), "Couldn't move Pick the paper to Done")
        XCTAssertEqual(BoardDrop.failure(on: .tag("doing"), title: "Pick the paper"), "Couldn't move Pick the paper to #doing")
    }

    func testTheBoardKnowsItsColumnTagsAndFindsACardAnywhere() {
        var tree = Tree.seed(now: Date(timeIntervalSince1970: 1_794_000_000))
        let newsletter = tree.children(of: rootID).first { $0.text == "Launch the newsletter" }!
        let kids = tree.children(of: newsletter.id)
        tree.addTag(kids[0].id, "researching")
        tree.addTag(kids[1].id, "doing")
        let gone = tree.add("Printer quote", todo: true, under: kids[2].id)
        tree.buds[tree.buds.firstIndex { $0.id == gone.id }!].fromState = "cancelled"
        let board = Board(tree: tree, center: newsletter.id)
        XCTAssertEqual(board.columnTags, ["researching", "doing"])
        XCTAssertEqual(board.card(kids[1].id)?.title, kids[1].text)
        XCTAssertEqual(board.card(gone.id)?.isCancelled, true, "found in the folded column too")
        XCTAssertNil(board.card(newsletter.id), "the board's own bud is no card")
    }

    private func bud(from: String, fromState: String) -> Bud {
        Bud(text: "Pick the paper", state: .open, from: from, fromState: fromState)
    }
}
