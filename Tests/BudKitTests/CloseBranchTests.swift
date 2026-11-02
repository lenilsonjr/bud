import XCTest
@testable import BudKit

final class CloseBranchTests: XCTestCase {
    /// A to-do with an open to-do, a done to-do, a note and a nested open to-do under the note.
    private func world() -> (Tree, parent: UUID, open: UUID, done: UUID, note: UUID, nested: UUID) {
        var t = Tree()
        let parent = t.add("Launch", todo: true, under: rootID)
        let open = t.add("Pick a name", todo: true, under: parent.id)
        let done = t.add("Book the venue", todo: true, under: parent.id)
        t.toggle(done.id)
        let note = t.add("Design notes", todo: false, under: parent.id)
        let nested = t.add("Warm, not corporate", todo: true, under: note.id)
        return (t, parent.id, open.id, done.id, note.id, nested.id)
    }

    func testCloseWithoutCascadeClosesOnlyTheBud() {
        var (t, parent, open, done, note, nested) = world()
        XCTAssertEqual(t.close(parent, cascade: false), [parent])
        XCTAssertEqual(t.bud(parent)?.state, .done)
        XCTAssertEqual(t.bud(open)?.state, .open)
        XCTAssertEqual(t.bud(done)?.state, .done)
        XCTAssertNil(t.bud(note)?.state)
        XCTAssertEqual(t.bud(nested)?.state, .open)
    }

    func testCloseWithCascadeClosesEveryOpenToDoInsideAndLeavesNotesAlone() {
        var (t, parent, open, done, note, nested) = world()
        let changed = t.close(parent, cascade: true)
        XCTAssertEqual(changed.first, parent)
        XCTAssertEqual(Set(changed), [parent, open, nested], "The done one and the note are not in the list")
        XCTAssertEqual(t.bud(open)?.state, .done)
        XCTAssertEqual(t.bud(nested)?.state, .done)
        XCTAssertNil(t.bud(note)?.state)
    }

    func testReopenSetsBackExactlyTheChangedIds() {
        var (t, parent, open, done, _, nested) = world()
        let changed = t.close(parent, cascade: true)
        t.reopen(changed)
        XCTAssertEqual(t.bud(parent)?.state, .open)
        XCTAssertEqual(t.bud(open)?.state, .open)
        XCTAssertEqual(t.bud(nested)?.state, .open)
        XCTAssertEqual(t.bud(done)?.state, .done, "What was done before stays done")
    }

    func testCloseRefusesANoteOrADoneToDo() {
        var (t, _, _, done, note, _) = world()
        XCTAssertEqual(t.close(note, cascade: true), [])
        XCTAssertEqual(t.close(done, cascade: true), [])
        XCTAssertEqual(t.close(UUID(), cascade: false), [])
    }
}

#if canImport(SwiftUI)
@MainActor
final class TickStoreTests: XCTestCase {
    func testTickReopensADoneToDoAtOnce() throws {
        let store = BudStore(fileURL: nil)
        let done = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.isDone })
        store.tick(done.id)
        XCTAssertEqual(store.tree.bud(done.id)?.state, .open)
        XCTAssertNil(store.modal)
    }

    func testTickClosesALeafToDoAtOnceWithTheToast() throws {
        let store = BudStore(fileURL: nil)
        let leaf = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.state == .open && store.tree.openCount(under: $0.id) == 0 })
        store.tick(leaf.id)
        XCTAssertEqual(store.tree.bud(leaf.id)?.state, .done)
        XCTAssertEqual(store.toasts.current?.action.message, "Closed \(leaf.text)")
        XCTAssertNil(store.modal)
    }

    func testTickOnAToDoWithOpenToDosInsideAsksFirst() throws {
        let store = BudStore(fileURL: nil)
        let newsletter = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        XCTAssertGreaterThan(store.tree.openCount(under: newsletter.id), 0)
        store.tick(newsletter.id)
        XCTAssertEqual(store.modal, .closeBranch(id: newsletter.id))
        XCTAssertEqual(store.tree.bud(newsletter.id)?.state, .open, "Nothing closes until the dialog answers")
    }

    func testCloseWithCascadePostsTheCountAndUndoReopensExactlyThose() async throws {
        let store = BudStore(fileURL: nil)
        let newsletter = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        let doneBefore = Set(store.tree.descendants(of: newsletter.id).filter { store.tree.bud($0)?.isDone == true })
        let open = store.tree.openCount(under: newsletter.id)
        store.close(newsletter.id, cascade: true)
        XCTAssertEqual(store.toasts.current?.action.message, "Closed Launch the newsletter and \(open) inside")
        XCTAssertEqual(store.tree.openCount(under: newsletter.id), 0)
        store.toasts.undo()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(store.tree.bud(newsletter.id)?.state, .open)
        XCTAssertEqual(store.tree.openCount(under: newsletter.id), open)
        let doneAfter = Set(store.tree.descendants(of: newsletter.id).filter { store.tree.bud($0)?.isDone == true })
        XCTAssertEqual(doneAfter, doneBefore, "What was done before stays done")
    }
}
#endif
