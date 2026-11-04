import XCTest
@testable import BudKit

final class PlacesTests: XCTestCase {
    private func newsletter(in t: Tree) throws -> Bud {
        try XCTUnwrap(t.children(of: rootID).first { $0.text == "Launch the newsletter" })
    }

    func testTrashKeepsTheBranchInTheTrashHeadFirstWithTheTime() throws {
        var t = Tree.seed()
        let thread = try newsletter(in: t)
        let when = Date(timeIntervalSince1970: 1_793_750_400)
        let count = t.descendants(of: thread.id).count
        t.trash(thread.id, at: when)
        XCTAssertEqual(t.trashed.count, 1)
        let branch = try XCTUnwrap(t.trashed.first)
        XCTAssertEqual(branch.id, thread.id)
        XCTAssertEqual(branch.head.text, "Launch the newsletter")
        XCTAssertEqual(branch.inside, count)
        XCTAssertEqual(branch.at, when)
    }

    func testRestoreByIdPutsTheBranchBackAndEmptiesItsSlot() throws {
        var t = Tree.seed()
        let thread = try newsletter(in: t)
        let before = t
        t.trash(thread.id)
        t.restore(thread.id)
        XCTAssertEqual(Set(t.buds), Set(before.buds))
        XCTAssertTrue(t.trashed.isEmpty)
        XCTAssertEqual(t.children(of: thread.id).map(\.id), before.children(of: thread.id).map(\.id))
    }

    func testRestoreOfABranchWhoseParentIsGoneLandsUnderEverything() throws {
        var t = Tree.seed()
        let thread = try newsletter(in: t)
        let child = try XCTUnwrap(t.children(of: thread.id).first)
        t.trash(child.id)
        t.trash(thread.id)
        t.deleteForever(thread.id)
        t.restore(child.id)
        XCTAssertEqual(t.bud(child.id)?.parent, rootID)
        XCTAssertEqual(t.children(of: rootID).last?.id, child.id, "After the last thread")
        XCTAssertTrue(t.trashed.isEmpty)
    }

    func testDeleteForeverAndEmptyTrashDropBranches() throws {
        var t = Tree.seed()
        let threads = t.children(of: rootID)
        XCTAssertGreaterThanOrEqual(threads.count, 2)
        t.trash(threads[0].id)
        t.trash(threads[1].id)
        t.deleteForever(threads[0].id)
        XCTAssertEqual(t.trashed.map(\.id), [threads[1].id])
        t.emptyTrash()
        XCTAssertTrue(t.trashed.isEmpty)
        XCTAssertNil(t.bud(threads[1].id), "Deleting never puts anything back")
    }

    func testTrashedBranchesStayOutOfSearchAndTheOutline() throws {
        var t = Tree.seed()
        let thread = try newsletter(in: t)
        t.trash(thread.id)
        XCTAssertFalse(TreeSearcher(tree: t).search("newsletter").contains { $0.id == thread.id })
        XCTAssertFalse(t.outline(expanded: []).contains { $0.id == thread.id })
    }

    func testAFileWithoutTheTrashKeyStillLoadsAndTheTrashRoundTrips() throws {
        var t = Tree.seed()
        let thread = try newsletter(in: t)
        t.trash(thread.id)
        let data = try JSONEncoder().encode(t)
        let back = try JSONDecoder().decode(Tree.self, from: data)
        XCTAssertEqual(back, t)
        let old = try JSONEncoder().encode(["buds": Tree.seed().buds])
        let loaded = try JSONDecoder().decode(Tree.self, from: old)
        XCTAssertTrue(loaded.trashed.isEmpty)
        XCTAssertEqual(loaded.buds.count, Tree.seed().buds.count)
    }

    func testArchivedIsTheClosedThreadsInTheirOrder() throws {
        var t = Tree.seed()
        XCTAssertTrue(t.archived().isEmpty)
        let threads = t.children(of: rootID)
        t.close(threads[1].id, cascade: true)
        t.close(threads[0].id, cascade: false)
        XCTAssertEqual(t.archived().map(\.id), [threads[0].id, threads[1].id])
        let child = try XCTUnwrap(t.children(of: threads[1].id).first)
        XCTAssertFalse(t.archived().contains { $0.id == child.id }, "Only threads, not what is inside them")
        t.reopen([threads[0].id])
        XCTAssertEqual(t.archived().map(\.id), [threads[1].id])
    }

    func testThePaletteListsEveryPlace() {
        let places = Destination.matching("").filter(\.isPlace).map(\.rawValue)
        XCTAssertEqual(places, ["Inbox", "Everything", "Archive", "Trash"])
    }
}

#if canImport(SwiftUI)
@MainActor
final class PlaceStoreTests: XCTestCase {
    func testOpeningAPlaceClearsTheLensAndACenterChangeClearsThePlace() throws {
        let store = BudStore(fileURL: nil)
        store.open(.today)
        store.openTrash()
        XCTAssertEqual(store.place, .trash)
        XCTAssertNil(store.lens)
        XCTAssertEqual(store.surface, .files)
        store.openArchive()
        XCTAssertEqual(store.place, .archive)
        store.open(.pinned)
        XCTAssertNil(store.place)
        store.openInbox()
        XCTAssertTrue(store.inboxOpen)
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first)
        store.center = thread.id
        XCTAssertNil(store.place)
        XCTAssertFalse(store.inboxOpen)
    }

    func testRestoreFromTheStorePostsAToastAndUndoTrashesAgain() async throws {
        let store = BudStore(fileURL: nil)
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        store.trash(thread.id)
        store.restore(thread.id)
        XCTAssertNotNil(store.tree.bud(thread.id))
        XCTAssertTrue(store.tree.trashed.isEmpty)
        XCTAssertEqual(store.toasts.current?.action.message, "Restored Launch the newsletter")
        store.toasts.undo()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(store.tree.bud(thread.id))
        XCTAssertEqual(store.tree.trashed.map(\.id), [thread.id])
    }

    func testDeleteForeverAsksFirstThroughTheModalAndThenDrops() throws {
        let store = BudStore(fileURL: nil)
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first)
        store.trash(thread.id)
        store.modal = .deleteForever(id: thread.id)
        XCTAssertEqual(store.modal?.id, thread.id)
        XCTAssertEqual(Modal.deleteForever(id: nil).id, Modal.emptyTrashID)
        store.deleteForever(thread.id)
        XCTAssertTrue(store.tree.trashed.isEmpty)
        XCTAssertNil(store.toasts.current, "Deleting for good is not undoable by toast")
    }

    func testTheCanvasLensFollowsTheTreeAndClearsToNothing() throws {
        let store = BudStore(fileURL: nil)
        XCTAssertTrue(store.canvasLight.isEmpty)
        store.canvasLens = .todos
        let open = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.state == .open })
        XCTAssertEqual(store.canvasLight[open.id], .hit)
        store.close(open.id, cascade: true)
        XCTAssertNotEqual(store.canvasLight[open.id], .hit, "A closed to-do leaves the lens at once")
        store.canvasLens = nil
        XCTAssertTrue(store.canvasLight.isEmpty)
    }
}
#endif
