import XCTest
@testable import BudKit

/// Not a `@MainActor` class: the Linux test runner's discovery cannot cast isolated test
/// methods, so each test hops onto the main actor itself.
final class CaptureRelayTests: XCTestCase {
    func testLinesWaitUntilAWindowListensThenArriveInOrder() async {
        await MainActor.run { relayKeepsOrder() }
    }

    @MainActor private func relayKeepsOrder() {
        let relay = CaptureRelay()
        relay.send(.init(text: "First", from: "Safari"))
        relay.send(.init(text: "Second", todo: true))
        XCTAssertEqual(relay.waiting, 2)
        var got: [CaptureRelay.Line] = []
        let window = relay.listen { got.append($0) }
        XCTAssertEqual(got.map(\.text), ["First", "Second"])
        XCTAssertEqual(relay.waiting, 0)
        relay.send(.init(text: "Third"))
        XCTAssertEqual(got.map(\.text), ["First", "Second", "Third"], "Delivered at once while listening")
        relay.stopListening(window)
        relay.send(.init(text: "Fourth"))
        XCTAssertEqual(relay.waiting, 1, "Waits again once the window is gone")
    }

    func testClosingOneWindowLeavesTheOthersListening() async {
        await MainActor.run { relayKeepsOtherWindows() }
    }

    @MainActor private func relayKeepsOtherWindows() {
        let relay = CaptureRelay()
        var first: [String] = []
        var second: [String] = []
        let one = relay.listen { first.append($0.text) }
        let two = relay.listen { second.append($0.text) }
        relay.send(.init(text: "To the newest"))
        XCTAssertEqual(first, [])
        XCTAssertEqual(second, ["To the newest"], "A line lands once, in the newest window")
        relay.stopListening(two)
        relay.send(.init(text: "Still heard"))
        XCTAssertEqual(first, ["Still heard"], "The window left open keeps listening")
        XCTAssertEqual(relay.waiting, 0)
        relay.stopListening(one)
        relay.send(.init(text: "Waits"))
        XCTAssertEqual(relay.waiting, 1)
    }

    func testALineKnowsWhereItCameFrom() {
        XCTAssertEqual(CaptureRelay.Line(text: "x", from: "Safari").body, "from Safari")
        XCTAssertEqual(CaptureRelay.Line(text: "x").body, "")
        XCTAssertEqual(CaptureRelay.Line(text: "x").source, "desktop")
    }
}

#if canImport(SwiftUI)
@MainActor
final class PanelCaptureStoreTests: XCTestCase {
    func testACapturedLineLandsInTheInboxWithItsSourceBodyAndKind() throws {
        let store = BudStore(fileURL: nil)
        let note = try XCTUnwrap(store.capture(CaptureRelay.Line(text: "Call the printer", from: "Safari")))
        XCTAssertEqual(note.parent, inboxID)
        XCTAssertEqual(note.source, "desktop")
        XCTAssertEqual(note.body, "from Safari")
        XCTAssertFalse(note.isTodo)
        let todo = try XCTUnwrap(store.capture(CaptureRelay.Line(text: "Order paper", todo: true)))
        XCTAssertTrue(todo.isTodo)
        XCTAssertEqual(todo.body, "")
    }
}
#endif
