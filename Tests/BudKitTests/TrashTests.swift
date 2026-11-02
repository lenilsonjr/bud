import XCTest
@testable import BudKit

final class TrashTests: XCTestCase {
    func testTrashHandsBackTheWholeBranchAndRestorePutsItBackAsItWas() throws {
        var t = Tree.seed()
        let thread = try XCTUnwrap(t.children(of: rootID).first { $0.text == "Launch the newsletter" })
        let branch = t.descendants(of: thread.id) + [thread.id]
        let before = t
        let trashed = t.trash(thread.id)
        XCTAssertEqual(Set(trashed.map(\.id)), Set(branch))
        XCTAssertNil(t.bud(thread.id))
        XCTAssertTrue(branch.allSatisfy { t.bud($0) == nil })
        t.restore(trashed)
        XCTAssertEqual(Set(t.buds), Set(before.buds), "Same ids, parents and order after a restore")
        XCTAssertEqual(t.children(of: thread.id).map(\.id), before.children(of: thread.id).map(\.id))
    }

    func testTrashingAnUnknownBudChangesNothing() {
        var t = Tree.seed()
        let before = t
        XCTAssertTrue(t.trash(UUID()).isEmpty)
        XCTAssertEqual(t, before)
    }

    func testRestoreSkipsABudThatIsAlreadyThere() throws {
        var t = Tree.seed()
        let thread = try XCTUnwrap(t.children(of: rootID).first)
        let count = t.buds.count
        t.restore([thread])
        XCTAssertEqual(t.buds.count, count)
    }
}

#if canImport(SwiftUI)
@MainActor
final class MenuStoreTests: XCTestCase {
    func testTrashPostsAToastAndUndoRestoresTheBranch() async throws {
        let store = BudStore(fileURL: nil)
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        let branch = store.tree.descendants(of: thread.id) + [thread.id]
        let before = store.tree
        store.trash(thread.id)
        XCTAssertTrue(branch.allSatisfy { store.tree.bud($0) == nil })
        XCTAssertEqual(store.toasts.current?.action.message, "Trashed Launch the newsletter")
        store.toasts.undo()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(Set(store.tree.buds), Set(before.buds))
    }

    func testTrashingTheCenterStepsOutToTheRoot() throws {
        let store = BudStore(fileURL: nil)
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first)
        store.center = thread.id
        store.trash(thread.id)
        XCTAssertEqual(store.center, rootID)
    }

    func testMakeTodoTurnsANoteIntoAnOpenToDoAndLeavesAToDoAlone() throws {
        let store = BudStore(fileURL: nil)
        let note = try XCTUnwrap(store.tree.walk(under: rootID).first { !$0.isTodo })
        store.makeTodo(note.id)
        XCTAssertEqual(store.tree.bud(note.id)?.state, .open)
        let done = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.isDone })
        store.makeTodo(done.id)
        XCTAssertEqual(store.tree.bud(done.id)?.state, .done)
        XCTAssertNil(store.toasts.current, "Changing kind is not undoable by toast")
    }
}
#endif
