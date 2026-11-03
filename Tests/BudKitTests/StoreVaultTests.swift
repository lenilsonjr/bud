#if canImport(SwiftUI)
import XCTest
@testable import BudKit

/// The store over a memory vault: every change goes to the vault and the tree is what comes back.
@MainActor
final class StoreVaultTests: XCTestCase {
    private func loaded() async -> (BudStore, MemoryVault) {
        let vault = MemoryVault(tree: Tree.seed())
        let store = BudStore(vault: vault)
        await store.reload()
        return (store, vault)
    }

    private func titles(_ records: [BudRecord]) -> Set<String> { Set(records.map(\.title)) }

    func testTheStoreLoadsTheSnapshotIntoItsTree() async {
        let (store, vault) = await loaded()
        let records = try? await vault.snapshot()
        XCTAssertEqual(store.tree.buds.count, records?.filter { $0.place != .trash }.count)
        XCTAssertEqual(store.tree.children(of: rootID).first?.text, "Launch the newsletter")
    }

    func testAddingABudReachesTheVault() async throws {
        let (store, vault) = await loaded()
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first)
        let planted = try XCTUnwrap(store.add("Book the printer", todo: true, under: thread.id))
        await store.settle()
        let records = try await vault.snapshot()
        let record = try XCTUnwrap(records.first { $0.path == planted.id.uuidString })
        XCTAssertEqual(record.title, "Book the printer")
        XCTAssertEqual(record.kind, .todo)
        XCTAssertEqual(record.parent, thread.id.uuidString)
        XCTAssertEqual(store.tree.bud(planted.id)?.text, "Book the printer")
    }

    func testAFreshStartEmptiesTheVaultAndTheTrash() async throws {
        let (store, vault) = await loaded()
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first)
        store.trash(thread.id)
        await store.settle()
        XCTAssertFalse(store.tree.trashed.isEmpty)
        store.center = try XCTUnwrap(store.tree.children(of: rootID).first?.id)
        store.freshStart(sample: false)
        await store.settle()
        XCTAssertTrue(store.tree.buds.isEmpty)
        XCTAssertTrue(store.tree.trashed.isEmpty)
        XCTAssertEqual(store.center, rootID)
        let records = try await vault.snapshot()
        XCTAssertTrue(records.isEmpty)
        XCTAssertEqual(store.toasts.current?.message, "Started over")
        XCTAssertNil(store.toasts.current?.undo)
    }

    func testAFreshStartCanPlantTheSampleWorldAgain() async throws {
        let vault = MemoryVault(tree: Tree())
        let store = BudStore(vault: vault)
        await store.reload()
        XCTAssertTrue(store.tree.buds.isEmpty)
        store.freshStart(sample: true)
        await store.settle()
        XCTAssertEqual(store.tree.children(of: rootID).first?.text, "Launch the newsletter")
        let records = try await vault.snapshot()
        XCTAssertEqual(titles(records), titles(Tree.seed().records()))
        XCTAssertEqual(store.toasts.current?.message, "Started over with the sample vault")
    }

    func testACaptureLandsInTheVaultsInbox() async throws {
        let (store, vault) = await loaded()
        let bud = try XCTUnwrap(store.capture("Buy stamps", source: "mac"))
        await store.settle()
        let record = try await vault.snapshot().first { $0.path == bud.id.uuidString }
        XCTAssertEqual(record?.place, .inbox)
        XCTAssertEqual(record?.source, "mac")
        XCTAssertEqual(store.tree.inbox().last?.text, "Buy stamps")
    }

    func testEditingTickingAndPinningReachTheVault() async throws {
        let (store, vault) = await loaded()
        let verify = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.text == "Verify the address" })
        store.update(verify.id, text: "Verify the sender address", todo: true)
        store.setBody(verify.id, "Check the records.")
        store.setPinned(verify.id, true)
        store.tick(verify.id)
        await store.settle()
        let record = try await vault.snapshot().first { $0.path == verify.id.uuidString }
        XCTAssertEqual(record?.title, "Verify the sender address")
        XCTAssertEqual(record?.body, "Check the records.")
        XCTAssertEqual(record?.pinned, true)
        XCTAssertEqual(record?.state, .done)
        XCTAssertEqual(store.tree.bud(verify.id)?.state, .done)
        store.tick(verify.id)
        await store.settle()
        let reopened = try await vault.snapshot().first { $0.path == verify.id.uuidString }
        XCTAssertEqual(reopened?.state, .open)
    }

    func testMoveReachesTheVaultAndUndoMovesItBack() async throws {
        let (store, vault) = await loaded()
        let name = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.text == "Pick a name" })
        let roadmap = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Q4 roadmap" })
        XCTAssertTrue(store.move(name.id, under: roadmap.id))
        await store.settle()
        let moved = try await vault.snapshot().first { $0.path == name.id.uuidString }
        XCTAssertEqual(moved?.parent, roadmap.id.uuidString)
        store.toasts.undo()
        try await Task.sleep(for: .milliseconds(100))
        await store.settle()
        let back = try await vault.snapshot().first { $0.path == name.id.uuidString }
        XCTAssertEqual(back?.parent, name.parent.uuidString)
    }

    func testTrashRestoreAndUndoGoThroughTheVault() async throws {
        let (store, vault) = await loaded()
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        let before = store.tree
        store.trash(thread.id)
        await store.settle()
        XCTAssertNil(store.tree.bud(thread.id))
        XCTAssertEqual(store.tree.trashed.count, 1)
        var records = try await vault.snapshot()
        XCTAssertEqual(records.first { $0.path == thread.id.uuidString }?.place, .trash)
        XCTAssertEqual(store.toasts.current?.action.message, "Trashed Launch the newsletter")

        store.restore(thread.id)
        await store.settle()
        XCTAssertEqual(store.tree, before)
        XCTAssertEqual(store.toasts.current?.action.message, "Restored Launch the newsletter")
        records = try await vault.snapshot()
        XCTAssertEqual(records.first { $0.path == thread.id.uuidString }?.place, .everything)

        store.toasts.undo()
        try await Task.sleep(for: .milliseconds(100))
        await store.settle()
        XCTAssertNil(store.tree.bud(thread.id))
        XCTAssertEqual(store.tree.trashed.count, 1)
    }

    func testDeletingForeverAndEmptyingTheTrashReachTheVault() async throws {
        let (store, vault) = await loaded()
        let roadmap = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Q4 roadmap" })
        let language = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Learn a language" })
        store.trash(roadmap.id)
        store.trash(language.id)
        store.deleteForever(roadmap.id)
        await store.settle()
        XCTAssertEqual(store.tree.trashed.map(\.id), [language.id])
        store.emptyTrash()
        await store.settle()
        XCTAssertTrue(store.tree.trashed.isEmpty)
        let records = try await vault.snapshot()
        XCTAssertEqual(records.filter { $0.place == .trash }.count, 0)
    }

    func testAWatchCallbackReloadsTheTree() async throws {
        let (store, vault) = await loaded()
        try await Task.sleep(for: .milliseconds(100))
        await vault.externalChange { $0.add("Added in the folder", todo: false, under: rootID) }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNotNil(store.tree.children(of: rootID).first { $0.text == "Added in the folder" })
    }

    func testTheCenterStaysPutAcrossReloadsUntilItsBudIsGone() async throws {
        let (store, vault) = await loaded()
        let name = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.text == "Pick a name" })
        store.center = name.id
        await vault.externalChange { $0.add("Added in the folder", todo: false, under: rootID) }
        await store.reload()
        XCTAssertEqual(store.center, name.id)
        XCTAssertNotNil(store.tree.children(of: rootID).first { $0.text == "Added in the folder" })
        await vault.externalChange { $0.remove(name.id) }
        await store.reload()
        XCTAssertEqual(store.center, rootID)
    }

    func testTheFileStoreStillWritesTheJSONFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = BudStore(fileURL: url)
        let bud = try XCTUnwrap(store.add("Plan the spring issue", todo: false, under: rootID))
        await store.settle()
        let tree = try JSONDecoder().decode(Tree.self, from: Data(contentsOf: url))
        XCTAssertEqual(tree.bud(bud.id)?.text, "Plan the spring issue")
        let again = BudStore(fileURL: url)
        XCTAssertEqual(again.tree.bud(bud.id)?.text, "Plan the spring issue")
    }
}
#endif
