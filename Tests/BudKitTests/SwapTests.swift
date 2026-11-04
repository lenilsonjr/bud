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

    func testSiblingsWithTheSameOrderStillTradePlaces() {
        var t = Tree()
        let a = t.add("A", todo: false, under: rootID)
        let b = t.add("B", todo: false, under: rootID)
        for i in t.buds.indices { t.buds[i].order = 1 }
        let before = t.children(of: rootID).map(\.id)
        XCTAssertTrue(t.swap(a.id, b.id))
        XCTAssertEqual(t.children(of: rootID).map(\.id), Array(before.reversed()))
    }

    func testASiblingIsTheOneBeforeOrAfterAndNilAtTheEnds() {
        let t = Tree.seed()
        let threads = t.children(of: rootID).map(\.id)
        XCTAssertNil(t.sibling(of: threads[0], offset: -1))
        XCTAssertEqual(t.sibling(of: threads[0], offset: 1), threads[1])
        XCTAssertEqual(t.sibling(of: threads[1], offset: -1), threads[0])
        XCTAssertNil(t.sibling(of: threads[threads.count - 1], offset: 1))
        XCTAssertNil(t.sibling(of: rootID, offset: 1))
    }

    func testReorderIgnoresBudsThatAreNotChildrenOfTheParent() {
        var t = Tree.seed()
        let threads = t.children(of: rootID).map(\.id)
        let inside = t.children(of: threads[0])[0].id
        t.reorder([threads[1], inside, threads[0]], under: rootID)
        XCTAssertEqual(Array(t.children(of: rootID).map(\.id).prefix(2)), [threads[1], threads[0]])
        XCTAssertEqual(t.bud(inside)?.parent, threads[0], "A bud from another parent stays where it is")
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
        // A sibling deleted outside the app is skipped; the rest still take the new order.
        let back = Array(wanted.reversed())
        try await vault.reorder([UUID().uuidString] + back, under: nil)
        let skipped = try await vault.snapshot().filter { $0.parent == nil && $0.place == .everything }.map(\.path)
        XCTAssertEqual(skipped, back)
    }
}
