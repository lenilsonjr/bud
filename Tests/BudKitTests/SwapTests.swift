import XCTest
@testable import BudKit

final class SwapTests: XCTestCase {
    func testSiblingsTradePlacesAndNothingElseDoes() {
        var t = Tree.seed()
        let threads = t.children(of: rootID).map(\.id)
        XCTAssertTrue(t.swap(threads[0], threads[2]))
        var expected = threads
        expected.swapAt(0, 2)
        XCTAssertEqual(t.children(of: rootID).map(\.id), expected)

        let inside = t.children(of: threads[0])[0].id
        let before = t.children(of: rootID).map(\.id)
        XCTAssertFalse(t.swap(threads[1], inside), "Not siblings")
        XCTAssertFalse(t.swap(threads[1], threads[1]), "The same bud")
        XCTAssertFalse(t.swap(threads[1], UUID()), "No such bud")
        XCTAssertEqual(t.children(of: rootID).map(\.id), before)
    }

    func testReorderSetsTheOrderAndKeepsTheRestAfter() {
        var t = Tree.seed()
        let threads = t.children(of: rootID).map(\.id)
        t.reorder([threads[2], threads[0]], under: rootID)
        XCTAssertEqual(t.children(of: rootID).map(\.id), [threads[2], threads[0]] + threads.filter { $0 != threads[2] && $0 != threads[0] })
    }

    func testTheMemoryVaultKeepsANewOrderAcrossAReload() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("swap-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let vault = MemoryVault(tree: Tree.seed(), fileURL: file)
        let threads = await vault.tree.children(of: rootID).map(\.id.uuidString)
        let wanted = Array(threads.reversed())
        try await vault.reorder(wanted, under: nil)
        let top = try await vault.snapshot().filter { $0.parent == nil && $0.place == .everything }.map(\.path)
        XCTAssertEqual(top, wanted)
        let again = MemoryVault(contentsOf: file)
        let reloaded = try await again.snapshot().filter { $0.parent == nil && $0.place == .everything }.map(\.path)
        XCTAssertEqual(reloaded, wanted)
        do {
            try await vault.reorder([UUID().uuidString], under: nil)
            XCTFail("An unknown path is refused")
        } catch {}
    }
}
