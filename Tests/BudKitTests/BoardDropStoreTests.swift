#if canImport(SwiftUI)
import XCTest
@testable import BudKit

/// A card dropped on a column, through the store and into the vault: the front matter it
/// writes, nothing beside it, and the one Undo that puts it back.
@MainActor
final class BoardDropStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_000_000)

    /// The newsletter thread as a board: researching, waiting and doing columns, one card done,
    /// one cancelled. Returns the store, the vault and the board's bud.
    private func loaded() async throws -> (BudStore, MemoryVault, UUID) {
        var tree = Tree.seed(now: now)
        let newsletter = try XCTUnwrap(tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        let kids = tree.children(of: newsletter.id)
        tree.addTag(kids[0].id, "researching")
        tree.addTag(kids[1].id, "waiting")
        tree.addTag(kids[1].id, "lawyer")
        let senderKids = tree.children(of: kids[1].id)
        tree.addTag(senderKids[0].id, "doing")
        tree.toggle(senderKids[1].id)
        let quote = tree.add("Printer quote", todo: true, under: kids[2].id, created: now)
        let gone = try XCTUnwrap(tree.buds.firstIndex { $0.id == quote.id })
        tree.buds[gone].fromState = "cancelled"
        let vault = MemoryVault(tree: tree)
        let store = BudStore(vault: vault)
        await store.reload()
        store.center = newsletter.id
        // "lawyer" is a tag with no column, so a drop leaves it alone.
        store.setBoardColumns(BoardColumns(tags: ["researching", "waiting", "doing"]), of: newsletter.id)
        await store.settle()
        return (store, vault, newsletter.id)
    }

    private func record(_ id: UUID, in vault: MemoryVault) async throws -> BudRecord {
        let records = try await vault.snapshot()
        return try XCTUnwrap(records.first { $0.path == id.uuidString })
    }

    /// Everything on the record but what a drop may write.
    private func rest(_ record: BudRecord) -> BudRecord {
        var rest = record
        rest.tags = []
        rest.state = nil
        rest.fromState = nil
        return rest
    }

    func testDroppingInATagColumnSetsItAndTakesTheOtherColumnTagsOut() async throws {
        let (store, vault, center) = try await loaded()
        let sender = try XCTUnwrap(store.board.columns.first { $0.kind == .tag("waiting") }?.cards.first)
        let before = try await record(sender.id, in: vault)
        XCTAssertTrue(store.drop(sender.id, on: .tag("doing")))
        await store.settle()
        let after = try await record(sender.id, in: vault)
        XCTAssertEqual(after.tags, ["lawyer", "doing"], "waiting is out, lawyer has no column and stays")
        XCTAssertEqual(after.state, .open)
        XCTAssertEqual(rest(after), rest(before), "nothing beside the tags changed")
        XCTAssertEqual(store.board(of: center).columns.first { $0.kind == .tag("doing") }?.cards.map(\.id).contains(sender.id), true)
        XCTAssertEqual(store.board(of: center).card(sender.id)?.tags, ["lawyer"])
    }

    func testDroppingInDoneClosesAndInOpenReopensWithoutColumnTags() async throws {
        let (store, vault, center) = try await loaded()
        let name = try XCTUnwrap(store.board.columns.first { $0.kind == .tag("researching") }?.cards.first)
        let before = try await record(name.id, in: vault)
        XCTAssertTrue(store.drop(name.id, on: .done))
        await store.settle()
        var after = try await record(name.id, in: vault)
        XCTAssertEqual(after.state, .done)
        XCTAssertEqual(after.tags, before.tags, "closing keeps the tags")
        XCTAssertEqual(rest(after), rest(before))
        XCTAssertEqual(store.board(of: center).columns.last?.cards.map(\.id).contains(name.id), true)

        XCTAssertTrue(store.drop(name.id, on: .open))
        await store.settle()
        after = try await record(name.id, in: vault)
        XCTAssertEqual(after.state, .open)
        XCTAssertEqual(after.tags, [])
        XCTAssertEqual(rest(after), rest(before))
        XCTAssertEqual(store.board(of: center).columns.first?.cards.map(\.id).contains(name.id), true)
    }

    func testDroppingInCancelledClosesWithTheMarkAndADropOutClearsIt() async throws {
        let (store, vault, center) = try await loaded()
        let doing = try XCTUnwrap(store.board.columns.first { $0.kind == .tag("doing") }?.cards.first)
        let before = try await record(doing.id, in: vault)
        XCTAssertTrue(store.drop(doing.id, on: .cancelled))
        await store.settle()
        var after = try await record(doing.id, in: vault)
        XCTAssertEqual(after.state, .done)
        XCTAssertEqual(after.fromState, "cancelled")
        XCTAssertEqual(after.tags, before.tags)
        XCTAssertEqual(rest(after), rest(before))
        XCTAssertEqual(store.board(of: center).cancelled.cards.map(\.id).contains(doing.id), true)

        let quote = try XCTUnwrap(store.board.cancelled.cards.first { $0.title == "Printer quote" })
        XCTAssertTrue(store.drop(quote.id, on: .tag("waiting")))
        await store.settle()
        after = try await record(quote.id, in: vault)
        XCTAssertEqual(after.state, .open)
        XCTAssertNil(after.fromState)
        XCTAssertEqual(after.tags, ["waiting"])
    }

    func testACardDroppedWhereItSitsChangesNothing() async throws {
        let (store, vault, _) = try await loaded()
        let name = try XCTUnwrap(store.board.columns.first { $0.kind == .tag("researching") }?.cards.first)
        let before = try await record(name.id, in: vault)
        XCTAssertFalse(store.drop(name.id, on: .tag("researching")))
        XCTAssertNil(store.toasts.current)
        await store.settle()
        let after = try await record(name.id, in: vault)
        XCTAssertEqual(after, before)
    }

    func testEveryDropIsOneToastWhoseUndoPutsTheFileBack() async throws {
        let (store, vault, center) = try await loaded()
        let sender = try XCTUnwrap(store.board.columns.first { $0.kind == .tag("waiting") }?.cards.first)
        let before = try await record(sender.id, in: vault)
        XCTAssertTrue(store.drop(sender.id, on: .cancelled))
        await store.settle()
        let toast = try XCTUnwrap(store.toasts.current)
        XCTAssertEqual(toast.action.message, "Cancelled \(sender.title)")
        XCTAssertNotNil(toast.action.undo, "a drop can be taken back")
        store.toasts.undo()
        try await settled(store)
        XCTAssertNil(store.toasts.current)
        let restored = try await record(sender.id, in: vault)
        XCTAssertEqual(restored, before)
        XCTAssertEqual(store.tree.bud(sender.id)?.tags, before.tags)
        XCTAssertEqual(store.board(of: center).columns.first { $0.kind == .tag("waiting") }?.cards.map(\.id).contains(sender.id), true)

        XCTAssertTrue(store.drop(sender.id, on: .tag("doing")))
        await store.settle()
        XCTAssertEqual(store.toasts.current?.action.message, "Tagged \(sender.title) #doing")
        store.toasts.undo()
        try await settled(store)
        let again = try await record(sender.id, in: vault)
        XCTAssertEqual(again, before, "the tags come back as they were")
    }

    /// Undo runs on the main actor a beat later; waits for it and for the write it queues.
    private func settled(_ store: BudStore) async throws {
        try await Task.sleep(for: .milliseconds(100))
        await store.settle()
    }
}
#endif
