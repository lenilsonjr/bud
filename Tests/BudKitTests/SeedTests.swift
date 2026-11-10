import XCTest
@testable import BudKit

final class SeedTests: XCTestCase {
    private let day: TimeInterval = 86_400

    func testTheStillMomentIsATuesdayMorning() {
        XCTAssertEqual(Tree.stillNow, Date(timeIntervalSince1970: 1_793_700_000))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(calendar.component(.weekday, from: Tree.stillNow), 3)
        XCTAssertEqual(calendar.component(.hour, from: Tree.stillNow), 10)
    }

    func testTwoSeedsOnTheSameClockAreTheSameWorld() {
        let first = Tree.seed(now: Tree.stillNow)
        let second = Tree.seed(now: Tree.stillNow)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.buds.map(\.id), second.buds.map(\.id))
        XCTAssertEqual(first.walk(under: rootID).map(\.text), second.walk(under: rootID).map(\.text))
        XCTAssertEqual(first.inbox().map(\.text), second.inbox().map(\.text))
    }

    func testTheSeedsIdsAreFixedAndItsOwn() {
        let seed = Tree.seed(now: Tree.stillNow)
        let ids = seed.buds.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(ids.first?.uuidString, "5EED0000-0000-4000-8000-000000000001")
        XCTAssertEqual(ids.last?.uuidString, "5EED0000-0000-4000-8000-\(String(format: "%012d", ids.count))")
        XCTAssertFalse(ids.contains(rootID))
        XCTAssertFalse(ids.contains(inboxID))
        XCTAssertFalse(ids.contains(warehouseID))
        // The order is the ids' order, so nothing decides it by hashing.
        let walk = seed.walk(under: rootID) + seed.inbox().flatMap { [$0] + seed.walk(under: $0.id) }
        XCTAssertEqual(walk.map(\.id).sorted { $0.uuidString < $1.uuidString }, ids.sorted { $0.uuidString < $1.uuidString })
    }

    func testTheSeedsDaysAreToldFromItsClock() throws {
        let now = Tree.stillNow
        let seed = Tree.seed(now: now)
        let name = try XCTUnwrap(seed.buds.first { $0.text == "Pick a name" })
        let verify = try XCTUnwrap(seed.buds.first { $0.text == "Verify the address" })
        let walk = try XCTUnwrap(seed.buds.first { $0.text == "A walk before the first meeting" })
        let printer = try XCTUnwrap(seed.buds.first { $0.text == "Ask the printer about paper samples" })
        XCTAssertEqual(name.due, now.addingTimeInterval(2 * day))
        XCTAssertEqual(verify.due, now.addingTimeInterval(-day))
        XCTAssertEqual(walk.when, now)
        XCTAssertEqual(printer.created, now.addingTimeInterval(-day))
        for bud in seed.buds {
            XCTAssertGreaterThanOrEqual(bud.created, now.addingTimeInterval(-day), bud.text)
            XCTAssertLessThanOrEqual(bud.created, now, bud.text)
        }
        XCTAssertEqual(seed.buds.max { $0.created < $1.created }?.text, "A recipe to try for the first issue")
        // Today, read on the same clock: the overdue to-do and the walk, whatever day it is run.
        let today = seed.today(on: now)
        XCTAssertEqual(today.due.map(\.text), ["Verify the address"])
        XCTAssertEqual(today.scheduled.map(\.text), ["A walk before the first meeting"])
    }

    func testTheSeedFollowsTheRealClockByDefault() throws {
        let before = Date()
        let seed = Tree.seed()
        let walk = try XCTUnwrap(seed.buds.first { $0.text == "A walk before the first meeting" })
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(walk.when), before)
        XCTAssertLessThanOrEqual(try XCTUnwrap(walk.when), Date())
    }
}
