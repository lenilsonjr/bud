import XCTest
@testable import BudKit

final class BoardColumnsEditTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_000_000)

    /// The newsletter thread with three tags inside, and tags elsewhere in the vault.
    private func world() -> (Tree, UUID) {
        var tree = Tree.seed(now: now)
        let newsletter = tree.children(of: rootID).first { $0.text == "Launch the newsletter" }!
        let kids = tree.children(of: newsletter.id)
        tree.addTag(kids[0].id, "researching")
        tree.addTag(kids[1].id, "waiting")
        tree.addTag(kids[1].id, "doing")
        let roadmap = tree.children(of: rootID).first { $0.text == "Q4 roadmap" }!
        for (i, bud) in ([roadmap] + tree.children(of: roadmap.id)).enumerated() {
            tree.addTag(bud.id, "someday")
            if i < 2 { tree.addTag(bud.id, "blocked") }
            if i < 1 { tree.addTag(bud.id, "this-week") }
        }
        return (tree, newsletter.id)
    }

    func testAColumnIsAddedAtTheEndOnceAndCleaned() {
        var columns = BoardColumns(tags: ["doing", "waiting"])
        columns.add("#blocked")
        XCTAssertEqual(columns.tags, ["doing", "waiting", "blocked"])
        columns.add("Doing")
        XCTAssertEqual(columns.tags, ["doing", "waiting", "blocked"], "A column it has, in any case, is not added twice")
        columns.add("1")
        columns.add("some day")
        XCTAssertEqual(columns.tags, ["doing", "waiting", "blocked"], "Not a tag")
        XCTAssertTrue(columns.has("BLOCKED"))
        XCTAssertFalse(columns.has("someday"))
    }

    func testAColumnIsTakenAwayByItsTagInAnyCase() {
        var columns = BoardColumns(tags: ["doing", "waiting", "blocked"])
        columns.remove("Waiting")
        XCTAssertEqual(columns.tags, ["doing", "blocked"])
        columns.remove("nothing")
        XCTAssertEqual(columns.tags, ["doing", "blocked"])
    }

    func testAColumnMovesToAPlaceOrByOne() {
        var columns = BoardColumns(tags: ["a", "b", "c", "d"])
        columns.move("d", to: 0)
        XCTAssertEqual(columns.tags, ["d", "a", "b", "c"])
        columns.move("a", to: 9)
        XCTAssertEqual(columns.tags, ["d", "b", "c", "a"], "Past the end is last")
        columns.move("zz", to: 0)
        XCTAssertEqual(columns.tags, ["d", "b", "c", "a"], "No column, no move")
        columns.moveLeft("d")
        XCTAssertEqual(columns.tags, ["d", "b", "c", "a"], "Nothing at the start")
        columns.moveRight("a")
        XCTAssertEqual(columns.tags, ["d", "b", "c", "a"], "Nothing at the end")
        columns.moveRight("d")
        columns.moveLeft("a")
        XCTAssertEqual(columns.tags, ["b", "d", "a", "c"])
        XCTAssertFalse(columns.canMoveLeft("b"))
        XCTAssertTrue(columns.canMoveLeft("d"))
        XCTAssertFalse(columns.canMoveRight("c"))
        XCTAssertTrue(columns.canMoveRight("A"))
        XCTAssertFalse(columns.canMoveRight("none"))
    }

    func testThePickerListsTheBoardsTagsThenTheOthersAndOffersANewOne() {
        let (tree, center) = world()
        let source = BoardTagSource(columns: BoardColumns(tags: ["waiting"]), inside: tree.walk(under: center), counts: tree.tagCounts())
        XCTAssertEqual(source.carried, ["researching", "waiting", "doing"])
        let all = BoardTagChoices.rows(for: "", in: source)
        XCTAssertEqual(all.onBoard, [.init(tag: "waiting", hasColumn: true), .init(tag: "researching"), .init(tag: "doing")], "The columns first, then the tags inside without one")
        XCTAssertEqual(all.others.map(\.tag), ["someday", "blocked", "this-week"], "Most used first")
        XCTAssertNil(all.create, "Nothing typed, nothing to create")
        XCTAssertEqual(all.pickable.map(\.tag), ["researching", "doing", "someday", "blocked", "this-week"])
        XCTAssertEqual(all.count, 5)

        let typed = BoardTagChoices.rows(for: "#Bl", in: source)
        XCTAssertEqual(typed.onBoard, [])
        XCTAssertEqual(typed.others.map(\.tag), ["blocked"])
        XCTAssertEqual(typed.create, "Bl", "What is typed can still be a new tag of its own, as the tag picker offers it")

        let new = BoardTagChoices.rows(for: "lawyer", in: source)
        XCTAssertEqual(new.onBoard, [])
        XCTAssertEqual(new.others, [])
        XCTAssertEqual(new.create, "lawyer")
        XCTAssertEqual(new.count, 1)
        XCTAssertEqual(BoardColumnText.create("lawyer"), "New tag column #lawyer")

        let column = BoardTagChoices.rows(for: "WAITING", in: source)
        XCTAssertEqual(column.onBoard, [.init(tag: "waiting", hasColumn: true)])
        XCTAssertNil(column.create, "A column it has is not created again")
        XCTAssertEqual(column.count, 0)

        let bad = BoardTagChoices.rows(for: "some day", in: source)
        XCTAssertNil(bad.create, "Not a tag")
    }

    func testThePickerPutsTheTagsThatStartWithTheTypedFirst() {
        let counts = [TagCount(tag: "ing-bound", buds: 3), TagCount(tag: "doing", buds: 2), TagCount(tag: "ingest", buds: 1)]
        let source = BoardTagSource(columns: BoardColumns(tags: []), carried: [], counts: counts)
        let rows = BoardTagChoices.rows(for: "ing", in: source)
        XCTAssertEqual(rows.others.map(\.tag), ["ing-bound", "ingest", "doing"])
        let many = BoardTagSource(columns: BoardColumns(tags: []), carried: ["c1", "c2"], counts: (1...9).map { TagCount(tag: "t\($0)", buds: 1) })
        let capped = BoardTagChoices.rows(for: "", in: many, limit: 3)
        XCTAssertEqual(capped.onBoard.map(\.tag), ["c1", "c2"])
        XCTAssertEqual(capped.others.map(\.tag), ["t1", "t2", "t3"], "Each group at most the limit; typing narrows")
        XCTAssertEqual(BoardTagChoices.rows(for: "t9", in: many, limit: 3).others.map(\.tag), ["t9"])
    }

    func testTheHeaderMenuMovesOrRemovesAColumnAndNothingElse() {
        var columns = BoardColumns(tags: ["a", "b", "c"])
        XCTAssertEqual(BoardColumnMenuItem.allCases.map(\.title), ["Move left", "Move right", "Remove column"])
        XCTAssertEqual(BoardColumnMenuItem.allCases.filter(\.startsGroup), [.remove])
        XCTAssertFalse(BoardColumnMenuItem.moveLeft.isEnabled(for: "a", in: columns))
        XCTAssertTrue(BoardColumnMenuItem.moveRight.isEnabled(for: "a", in: columns))
        XCTAssertFalse(BoardColumnMenuItem.moveRight.isEnabled(for: "c", in: columns))
        XCTAssertTrue(BoardColumnMenuItem.remove.isEnabled(for: "b", in: columns))
        XCTAssertFalse(BoardColumnMenuItem.remove.isEnabled(for: "z", in: columns))
        BoardColumnMenuItem.moveRight.apply(to: &columns, for: "a")
        XCTAssertEqual(columns.tags, ["b", "a", "c"])
        BoardColumnMenuItem.moveLeft.apply(to: &columns, for: "c")
        XCTAssertEqual(columns.tags, ["b", "c", "a"])
        BoardColumnMenuItem.remove.apply(to: &columns, for: "c")
        XCTAssertEqual(columns.tags, ["b", "a"])
    }

    func testADropFindsItsGapFromTheColumnsFrames() {
        let tags = ["a", "b", "c"]
        let frames = [
            "a": CGRect(x: 0, y: 0, width: 100, height: 400),
            "b": CGRect(x: 110, y: 0, width: 100, height: 400),
            "c": CGRect(x: 220, y: 0, width: 100, height: 400),
        ]
        XCTAssertEqual(BoardColumnDrop.under(CGPoint(x: 10, y: 50), frames: frames, tags: tags)?.gap, 0)
        XCTAssertEqual(BoardColumnDrop.under(CGPoint(x: 60, y: 50), frames: frames, tags: tags)?.gap, 1)
        XCTAssertEqual(BoardColumnDrop.under(CGPoint(x: 200, y: 50), frames: frames, tags: tags)?.gap, 2)
        XCTAssertEqual(BoardColumnDrop.under(CGPoint(x: 900, y: 50), frames: frames, tags: tags)?.gap, 3)
        XCTAssertNil(BoardColumnDrop.under(CGPoint(x: 900, y: 50), frames: [:], tags: tags), "No frames yet: no gap, so no move")
        XCTAssertNil(BoardColumnDrop.under(CGPoint(x: 900, y: 50), frames: ["x": frames["a"]!], tags: tags))

        let before = BoardColumnDrop(gap: 1)
        XCTAssertEqual(before.line(on: "b", in: tags), .before)
        XCTAssertNil(before.line(on: "a", in: tags))
        XCTAssertNil(before.line(on: "c", in: tags))
        let after = BoardColumnDrop(gap: 3)
        XCTAssertEqual(after.line(on: "c", in: tags), .after)
        XCTAssertNil(after.line(on: "b", in: tags))
        XCTAssertNil(BoardColumnDrop(gap: 2).line(on: "x", in: []))

        XCTAssertEqual(BoardColumnDrop(gap: 3).index(moving: "a", in: tags), 2, "The gaps count its old place")
        XCTAssertEqual(BoardColumnDrop(gap: 0).index(moving: "c", in: tags), 0)
        XCTAssertEqual(BoardColumnDrop(gap: 2).index(moving: "C", in: tags), 2)
    }

    func testAColumnInHandDrawsNoLineBesideItself() {
        let tags = ["a", "b", "c"]
        let own = BoardColumnDrag(tag: "b", point: .zero, drop: BoardColumnDrop(gap: 1))
        XCTAssertNil(own.line(on: "b", in: tags), "Before itself changes nothing")
        XCTAssertNil(own.target(in: tags), "So a drop there moves nothing")
        let next = BoardColumnDrag(tag: "b", point: .zero, drop: BoardColumnDrop(gap: 2))
        XCTAssertNil(next.line(on: "c", in: tags), "After itself changes nothing")
        XCTAssertNil(next.target(in: tags))
        let far = BoardColumnDrag(tag: "b", point: .zero, drop: BoardColumnDrop(gap: 3))
        XCTAssertEqual(far.line(on: "c", in: tags), .after)
        XCTAssertEqual(far.target(in: tags), 2)
        XCTAssertEqual(BoardColumnDrag(tag: "c", point: .zero, drop: BoardColumnDrop(gap: 0)).target(in: tags), 0)
        XCTAssertNil(BoardColumnDrag(tag: "b", point: .zero).line(on: "c", in: tags), "No gap, no line")
        XCTAssertNil(BoardColumnDrag(tag: "b", point: .zero).target(in: tags))
        var columns = BoardColumns(tags: tags)
        columns.move("b", to: far.target(in: tags)!)
        XCTAssertEqual(columns.tags, ["a", "c", "b"])
    }
}

#if canImport(SwiftUI)
/// The edits through the store, which exists only where SwiftUI does.
@MainActor
final class BoardColumnsStoreTests: XCTestCase {
    func testPickingAddsAtTheEndAndTheMenuMovesOrRemovesWithoutTouchingATag() async throws {
        var tree = Tree.seed()
        let newsletter = try XCTUnwrap(tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        let kids = tree.children(of: newsletter.id)
        tree.addTag(kids[0].id, "researching")
        tree.addTag(kids[1].id, "waiting")
        let roadmap = try XCTUnwrap(tree.children(of: rootID).first { $0.text == "Q4 roadmap" })
        tree.addTag(roadmap.id, "someday")
        let vault = MemoryVault(tree: tree)
        let store = BudStore(vault: vault, tree: tree)
        await store.settle()
        store.center = newsletter.id
        let before = store.tree
        XCTAssertEqual(store.boards, [:])
        XCTAssertEqual(store.boardColumns(of: newsletter.id).tags, ["researching", "waiting"], "The default, spelled out")

        let source = store.boardTagSource(of: newsletter.id)
        XCTAssertEqual(source.columns.tags, ["researching", "waiting"])
        XCTAssertEqual(source.carried, ["researching", "waiting"])
        XCTAssertEqual(source.counts.map(\.tag), ["researching", "someday", "waiting"])
        let choices = BoardTagChoices.rows(for: "", in: source)
        XCTAssertEqual(choices.onBoard.map(\.tag), ["researching", "waiting"])
        XCTAssertTrue(choices.onBoard.allSatisfy(\.hasColumn))
        XCTAssertEqual(choices.others.map(\.tag), ["someday"])
        XCTAssertEqual(BoardTagChoices.rows(for: "blocked", in: source).create, "blocked")

        store.moveBoardColumn("waiting", to: 1, of: newsletter.id)
        store.editBoardColumns(of: newsletter.id) { _ in }
        XCTAssertEqual(store.boards, [:], "An edit that changes nothing keeps the default board, so new tags still get columns")

        store.addBoardColumn("someday", of: newsletter.id)
        XCTAssertEqual(store.board.columns.map(\.kind), [.open, .tag("researching"), .tag("waiting"), .tag("someday"), .done], "At the end")
        store.addBoardColumn("blocked", of: newsletter.id)
        XCTAssertEqual(store.boardColumns(of: newsletter.id).tags, ["researching", "waiting", "someday", "blocked"], "A tag no bud carries gets its column too")

        store.moveBoardColumn("blocked", to: 0, of: newsletter.id)
        XCTAssertEqual(store.boardColumns(of: newsletter.id).tags, ["blocked", "researching", "waiting", "someday"])
        store.editBoardColumns(of: newsletter.id) { BoardColumnMenuItem.moveRight.apply(to: &$0, for: "blocked") }
        XCTAssertEqual(store.boardColumns(of: newsletter.id).tags, ["researching", "blocked", "waiting", "someday"])

        store.removeBoardColumn("researching", of: newsletter.id)
        XCTAssertEqual(store.board.columns.map(\.kind), [.open, .tag("blocked"), .tag("waiting"), .tag("someday"), .done])
        XCTAssertEqual(store.tree, before, "No bud's tags changed")
        let name = try XCTUnwrap(store.tree.bud(kids[0].id))
        XCTAssertEqual(name.allTags, ["researching"], "The card keeps its tag and goes to Open")
        XCTAssertTrue(store.board.columns[0].cards.contains { $0.id == kids[0].id })
        XCTAssertEqual(store.board.columns[0].cards.first { $0.id == kids[0].id }?.tags, ["researching"])

        await store.settle()
        let stored = try await vault.shared(.board)
        XCTAssertEqual(stored, [newsletter.id.uuidString: "{\"tags\":[\"blocked\",\"waiting\",\"someday\"]}"], "Kept, so the column stays off everywhere")
    }
}
#endif
