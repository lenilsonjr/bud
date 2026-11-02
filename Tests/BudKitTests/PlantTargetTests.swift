import XCTest
@testable import BudKit

final class PlantTargetTests: XCTestCase {
    func testEverythingSendsALineToTheInboxAndAnyBudTakesItInside() {
        let t = Tree.seed()
        let thread = t.children(of: rootID)[0]
        XCTAssertEqual(PlantTarget.forCenter(rootID), .inbox)
        XCTAssertEqual(PlantTarget.forCenter(thread.id), .under(thread.id))
        XCTAssertEqual(PlantTarget.inbox.title(in: t), "New bud in Inbox")
        XCTAssertEqual(PlantTarget.under(thread.id).title(in: t), "New bud under \(thread.text)")
    }
}

#if canImport(SwiftUI)
@MainActor
final class PlantStoreTests: XCTestCase {
    func testPlantingFromEverythingCapturesWithTheSourceAndFromAThreadAddsUnderIt() throws {
        let store = BudStore(fileURL: nil)
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first)
        let before = store.tree.inbox().count
        let captured = try XCTUnwrap(store.plant("From the sofa", todo: true, at: .inbox, source: "tv"))
        XCTAssertEqual(captured.parent, inboxID)
        XCTAssertEqual(captured.source, "tv")
        XCTAssertFalse(captured.isTodo, "A capture is a note until it is enriched")
        XCTAssertEqual(store.tree.inbox().count, before + 1)
        let added = try XCTUnwrap(store.plant("Under the thread", todo: true, at: .under(thread.id), source: "tv"))
        XCTAssertEqual(added.parent, thread.id)
        XCTAssertTrue(added.isTodo)
        XCTAssertNil(added.source)
        XCTAssertEqual(store.tree.inbox().count, before + 1, "Nothing more in the Inbox")
    }
}
#endif
