import XCTest
@testable import BudKit

final class BoardTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    /// The newsletter thread with a few tags, one done, one cancelled: the board's world.
    private func world() -> (Tree, UUID) {
        var tree = Tree.seed(now: now)
        let newsletter = tree.children(of: rootID).first { $0.text == "Launch the newsletter" }!
        let kids = tree.children(of: newsletter.id)
        let name = kids[0], sender = kids[1], design = kids[2]
        tree.addTag(name.id, "researching")
        tree.addTag(sender.id, "waiting")
        tree.addTag(sender.id, "doing")
        let senderKids = tree.children(of: sender.id)
        tree.addTag(senderKids[0].id, "doing")
        tree.toggle(senderKids[1].id)
        tree.addTag(senderKids[1].id, "waiting")
        let cancelled = tree.add("Printer quote", todo: true, under: design.id)
        tree.buds[tree.buds.firstIndex { $0.id == cancelled.id }!].fromState = "cancelled"
        return (tree, newsletter.id)
    }

    func testOpenComesFirstThenTheTagsInTheirOrderThenDoneAndCancelledFolded() {
        let (tree, center) = world()
        let board = Board(tree: tree, center: center)
        XCTAssertEqual(board.title, "Launch the newsletter")
        XCTAssertEqual(board.inside, tree.descendants(of: center).count)
        XCTAssertEqual(board.scope, "Everything inside · \(board.inside)")
        XCTAssertEqual(board.columns.map(\.kind), [.open, .tag("researching"), .tag("waiting"), .tag("doing"), .done])
        XCTAssertEqual(board.cancelled.kind, .cancelled)
        XCTAssertEqual(board.cancelled.cards.map(\.title), ["Printer quote"])
        XCTAssertEqual(board.columns[4].cards.map(\.title), ["Verify the address"], "Done beats the tag it carries")
        XCTAssertEqual(board.columns[1].cards.map(\.title), ["Pick a name"])
        XCTAssertEqual(board.columns[2].cards.map(\.title), ["Set up the sender"], "The first column in order takes it")
        XCTAssertEqual(board.columns[2].cards[0].tags, ["doing"], "The other tags stay on the card")
        XCTAssertEqual(board.columns[3].cards.map(\.title), ["Domain records are in the shared doc"])
        XCTAssertTrue(board.columns[0].cards.contains { $0.title == "Design notes" }, "A note is Open")
        XCTAssertTrue(board.columns[0].cards.contains { $0.title == "Shortlist three candidates" }, "A grandchild is on the board too")
        XCTAssertFalse(board.columns[0].cards.contains { $0.title == "Pick a name" })
        let all = board.columns.flatMap(\.cards) + board.cancelled.cards
        XCTAssertEqual(all.count, board.inside, "Every bud inside is on one card")
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
    }

    func testThePersonsOrderIsTheColumnsAndTheRestGoToOpen() {
        let (tree, center) = world()
        let board = Board(tree: tree, center: center, tags: ["doing", "someday"])
        XCTAssertEqual(board.columns.map(\.kind), [.open, .tag("doing"), .tag("someday"), .done])
        XCTAssertEqual(board.columns[1].cards.map(\.title), ["Set up the sender", "Domain records are in the shared doc"])
        XCTAssertEqual(board.columns[1].cards[0].tags, ["waiting"])
        XCTAssertEqual(board.columns[2].cards, [], "A column with nothing in it is still a column")
        let name = board.columns[0].cards.first { $0.title == "Pick a name" }
        XCTAssertEqual(name?.tags, ["researching"], "A tag without a column shows on the card")
    }

    func testAColumnsTagMatchesInAnyCase() {
        let (tree, center) = world()
        let board = Board(tree: tree, center: center, tags: ["Researching"])
        XCTAssertEqual(board.columns[1].cards.map(\.title), ["Pick a name"])
        XCTAssertEqual(board.columns[1].cards[0].tags, [])
    }

    func testTheDefaultColumnsAreTheTagsInUseInReadingOrder() {
        let (tree, center) = world()
        XCTAssertEqual(BoardColumns.inUse(by: tree.walk(under: center)), ["researching", "waiting", "doing"])
        XCTAssertEqual(BoardColumns.inUse(by: []), [])
        let board = Board(tree: Tree(), center: rootID)
        XCTAssertEqual(board.columns.map(\.kind), [.open, .done])
        XCTAssertEqual(board.inside, 0)
    }

    func testACardCarriesTheTrailTheDaysTheTagsAndWhatIsInside() {
        let (tree, center) = world()
        let board = Board(tree: tree, center: center)
        let name = board.columns[1].cards[0]
        XCTAssertEqual(name.trail, ["Launch the newsletter"])
        XCTAssertEqual(name.trailText, "Launch the newsletter")
        XCTAssertEqual(name.inside, 3)
        XCTAssertEqual(name.insideText, "3 inside")
        XCTAssertTrue(name.isTodo)
        XCTAssertFalse(name.isDone)
        XCTAssertEqual(name.dueText(now: now, calendar: calendar), "Due " + DayText.relative(name.due!, now: now, calendar: calendar))
        XCTAssertNil(name.whenText(now: now, calendar: calendar))
        let shortlist = board.columns[0].cards.first { $0.title == "Shortlist three candidates" }!
        XCTAssertEqual(shortlist.trailText, "Launch the newsletter › Pick a name")
        XCTAssertNil(shortlist.insideText)
        let done = board.columns[4].cards[0]
        XCTAssertTrue(done.isDone)
        XCTAssertEqual(done.tags, ["waiting"])
    }

    func testTheBoardOfEverythingTrailsFromEverything() {
        let (tree, _) = world()
        let board = Board(tree: tree, center: rootID)
        let leaf = board.columns[0].cards.first { $0.title == "Shortlist three candidates" }!
        XCTAssertEqual(leaf.trailText, "Everything › Launch the newsletter › Pick a name")
        XCTAssertFalse(board.columns[0].cards.contains { $0.title == "Ask the printer about paper samples" }, "The Inbox is not inside")
    }

    func testADayReadsRelativeToNow() {
        let day: TimeInterval = 86_400
        XCTAssertEqual(DayText.relative(now, now: now, calendar: calendar), "Today")
        XCTAssertEqual(DayText.relative(now.addingTimeInterval(day), now: now, calendar: calendar), "Tomorrow")
        XCTAssertEqual(DayText.relative(now.addingTimeInterval(-day), now: now, calendar: calendar), "Yesterday")
        let inThree = now.addingTimeInterval(3 * day)
        XCTAssertEqual(DayText.relative(inThree, now: now, calendar: calendar).count, 3, "A weekday, short")
        XCTAssertEqual(DayText.relative(now.addingTimeInterval(7 * day), now: now, calendar: calendar), DayText.short(now.addingTimeInterval(7 * day), calendar: calendar))
        XCTAssertEqual(DayText.relative(now.addingTimeInterval(-3 * day), now: now, calendar: calendar), DayText.short(now.addingTimeInterval(-3 * day), calendar: calendar))
    }

    func testColumnsAreCleanedAndOnceEachHoweverTheyAreMade() throws {
        let text = "{\"tags\":[\"#Doing\",\"doing\",\"waiting\",\"1\",\"some day\"]}"
        let columns = try JSONDecoder().decode(BoardColumns.self, from: Data(text.utf8))
        XCTAssertEqual(columns.tags, ["Doing", "waiting"])
        XCTAssertEqual(BoardColumns(tags: ["#Doing", "doing", "waiting", "1", "some day"]).tags, ["Doing", "waiting"])
        let (tree, center) = world()
        let twice = Board(tree: tree, center: center, tags: BoardColumns(tags: ["doing", "doing"]).tags)
        XCTAssertEqual(twice.columns.map(\.kind), [.open, .tag("doing"), .done], "No two columns share an id")
        let encoded = try JSONEncoder().encode(BoardColumns(tags: ["a", "b"]))
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "{\"tags\":[\"a\",\"b\"]}")
    }

    func testACancelledBudIsOneWhoseSourceCancelledIt() {
        var bud = Bud(text: "Call", state: .open)
        XCTAssertFalse(bud.isCancelled)
        bud.fromState = "cancelled"
        XCTAssertTrue(bud.isCancelled)
        bud.fromState = "closed 2026-11-05T21:00:00Z"
        XCTAssertFalse(bud.isCancelled)
    }
}

#if canImport(SwiftUI)
/// The columns through the store, which exists only where SwiftUI does.
@MainActor
final class BoardStoreTests: XCTestCase {
    func testTheColumnsSetOnOneDeviceAreReadByAnotherOnTheSameVault() async throws {
        let vault = MemoryVault(tree: Tree.seed())
        let mac = BudStore(vault: vault)
        await mac.settle()
        let newsletter = try XCTUnwrap(mac.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        mac.center = newsletter.id
        for bud in mac.tree.children(of: newsletter.id).prefix(2) { mac.addTag(bud.id, "waiting") }
        await mac.settle()
        XCTAssertEqual(mac.board.columns.map(\.kind), [.open, .tag("waiting"), .done], "Nothing stored: the tags in use")

        mac.setBoardColumns(BoardColumns(tags: ["doing", "waiting"]), of: newsletter.id)
        XCTAssertEqual(mac.board.columns.map(\.kind), [.open, .tag("doing"), .tag("waiting"), .done], "Shown at once")
        await mac.settle()
        let stored = try await vault.shared(.board)
        XCTAssertEqual(stored, [newsletter.id.uuidString: "{\"tags\":[\"doing\",\"waiting\"]}"])

        let phone = BudStore(vault: vault)
        await phone.reloadBoards()
        XCTAssertEqual(phone.boards, [newsletter.id: BoardColumns(tags: ["doing", "waiting"])])
        XCTAssertEqual(phone.board(of: newsletter.id).columns.map(\.kind), [.open, .tag("doing"), .tag("waiting"), .done])
        XCTAssertEqual(phone.board(of: rootID).columns.map(\.kind), [.open, .tag("waiting"), .done], "Another bud's board keeps its default")

        phone.setBoardColumns(nil, of: newsletter.id)
        await phone.settle()
        await mac.reloadBoards()
        XCTAssertEqual(mac.boards, [:])
        XCTAssertEqual(mac.board.columns.map(\.kind), [.open, .tag("waiting"), .done])
    }

    func testAnEntryAnotherBuildWroteBadlyIsSkipped() async throws {
        let vault = MemoryVault(tree: Tree.seed())
        try await vault.setShared(.board, "not-an-id", "{\"tags\":[\"a\"]}")
        try await vault.setShared(.board, rootID.uuidString, "not json")
        try await vault.setShared(.board, inboxID.uuidString, "{\"tags\":[\"inbox\"]}")
        let store = BudStore(vault: vault)
        await store.reloadBoards()
        XCTAssertEqual(store.boards, [inboxID: BoardColumns(tags: ["inbox"])])
    }

    func testAPictureIsAskedOfTheVaultOnceAndKeptDecoded() async throws {
        var tree = Tree()
        let bud = tree.add("Living room board", todo: false, under: rootID)
        let bare = tree.add("Bare", todo: false, under: rootID)
        let vault = MemoryVault(tree: tree)
        // A 1 by 1 PNG, as small as one gets.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=")!
        await vault.keepPicture(png, of: bud.id.uuidString)
        let store = BudStore(vault: vault)
        await store.settle()
        if case .unknown = store.pictureState(of: bud.id) {} else { XCTFail("Nothing asked yet") }
        await store.loadPicture(of: bud.id)
        let picture = try XCTUnwrap(store.pictureState(of: bud.id).picture)
        XCTAssertEqual(picture.image.width, 1)
        await store.loadPicture(of: bare.id)
        if case .none = store.pictureState(of: bare.id) {} else { XCTFail("A bud without a picture is known to have none") }
        await vault.keepPicture(nil, of: bud.id.uuidString)
        await store.loadPicture(of: bud.id)
        XCTAssertNotNil(store.pictureState(of: bud.id).picture, "Asked once; the answer is kept")
        store.forgetPictures()
        if case .unknown = store.pictureState(of: bud.id) {} else { XCTFail("Forgotten") }
        store.keepPicture(nil, of: bud.id)
        if case .none = store.pictureState(of: bud.id) {} else { XCTFail("Kept as none without asking") }
    }
}
#endif
