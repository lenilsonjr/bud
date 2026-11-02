import XCTest
@testable import BudKit

#if canImport(SwiftUI)
@MainActor
final class CaptureStoreTests: XCTestCase {
    func testCaptureTrimsAndLandsInTheInboxWithTheToast() throws {
        let store = BudStore(fileURL: nil)
        let before = store.tree.inbox().count
        let bud = try XCTUnwrap(store.capture("  Water the ferns \n"))
        XCTAssertEqual(bud.text, "Water the ferns")
        XCTAssertEqual(bud.parent, inboxID)
        XCTAssertEqual(bud.source, BudStore.platformSource)
        XCTAssertEqual(store.tree.inbox().count, before + 1)
        XCTAssertEqual(store.toasts.current?.action.message, "Captured to the Inbox")
    }

    func testGoingToAnInboxBudOpensTheInboxNotTheCanvas() throws {
        let store = BudStore(fileURL: nil)
        let captured = try XCTUnwrap(store.capture("A thought"))
        store.go(to: captured.id, inFiles: false)
        XCTAssertTrue(store.inboxOpen)
        XCTAssertEqual(store.surface, .files)
        XCTAssertEqual(store.center, rootID, "an inbox bud never becomes the center")
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first)
        store.go(to: thread.id, inFiles: false)
        XCTAssertFalse(store.inboxOpen)
        XCTAssertEqual(store.center, thread.id)
        XCTAssertEqual(store.surface, .canvas)
    }

    func testCaptureRefusesABlankLine() {
        let store = BudStore(fileURL: nil)
        let before = store.tree
        XCTAssertNil(store.capture("   \n "))
        XCTAssertEqual(store.tree, before)
        XCTAssertNil(store.toasts.current)
    }

    func testUndoingACaptureTakesItBack() async throws {
        let store = BudStore(fileURL: nil)
        let bud = try XCTUnwrap(store.capture("Water the ferns"))
        store.toasts.undo()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(store.tree.bud(bud.id))
    }

    func testMovePostsAToastAndUndoMovesItBack() async throws {
        let store = BudStore(fileURL: nil)
        let target = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Q4 roadmap" })
        let captured = try XCTUnwrap(store.tree.inbox().first)
        store.move(captured.id, under: target.id)
        XCTAssertEqual(store.tree.bud(captured.id)?.parent, target.id)
        XCTAssertEqual(store.toasts.current?.action.message, "Moved to Q4 roadmap")
        store.toasts.undo()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(store.tree.bud(captured.id)?.parent, inboxID)
    }

    func testTheInboxCountDropsWhenACaptureIsMovedOut() throws {
        let store = BudStore(fileURL: nil)
        let before = store.tree.inbox().count
        let captured = try XCTUnwrap(store.tree.inbox().first)
        let target = try XCTUnwrap(store.tree.children(of: rootID).first)
        XCTAssertTrue(store.move(captured.id, under: target.id))
        XCTAssertEqual(store.tree.inbox().count, before - 1)
    }

    func testMoveUnderItsOwnDescendantIsRefusedWithoutAToast() throws {
        let store = BudStore(fileURL: nil)
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        let child = try XCTUnwrap(store.tree.children(of: thread.id).first)
        let before = store.tree
        store.move(thread.id, under: child.id)
        XCTAssertEqual(store.tree, before)
        XCTAssertNil(store.toasts.current)
    }
}
#endif
