import XCTest
@testable import BudKit

final class TVFilesTextTests: XCTestCase {
    private var tree: Tree { Tree.seed() }

    func testThePagesCarryTheSidebarsCounts() {
        let tree = tree
        XCTAssertEqual(TVFilesText.count(.inbox, in: tree), tree.inbox().count)
        let today = tree.today()
        XCTAssertEqual(TVFilesText.count(.today, in: tree), today.due.count + today.scheduled.count)
        XCTAssertEqual(TVFilesText.count(.todos, in: tree), tree.openTodos().reduce(0) { $0 + $1.todos.count })
        XCTAssertEqual(TVFilesText.count(.pinned, in: tree), 1)
        XCTAssertNil(TVFilesText.count(.everything, in: tree), "Everything shows no count, as on the Mac")
    }

    func testTheInboxRowsSayWhenTheyWereCaptured() {
        let rows = TVFilesText.rows(.inbox, in: tree)
        XCTAssertEqual(rows.map(\.title), tree.inbox().map(\.text))
        XCTAssertEqual(rows.first?.caption, "Captured yesterday")
        XCTAssertEqual(rows.last?.caption, "Captured today")
        XCTAssertTrue(rows.first!.opens, "The printer question has a bud inside, so a click goes in")
        XCTAssertFalse(rows.last!.opens)
    }

    func testTodayListsTheDueBeforeTheScheduled() {
        let rows = TVFilesText.rows(.today, in: tree)
        XCTAssertEqual(rows.map(\.title), ["Verify the address", "A walk before the first meeting"])
        guard case let .due(date)? = rows.first?.tag else { return XCTFail("The overdue to-do is tagged Due") }
        XCTAssertEqual(TVFilesText.label(.due(date)), "Overdue · " + TVFilesText.label(.scheduled(date))!, "The seed's address check was due yesterday")
        guard case .scheduled = rows.last?.tag else { return XCTFail("The walk is tagged with its day") }
        XCTAssertEqual(rows.first?.caption, "Launch the newsletter › Set up the sender")
    }

    func testTheOpenTodosKeepTheirThreadsOrder() {
        let rows = TVFilesText.rows(.todos, in: tree)
        XCTAssertEqual(rows.first?.title, "Launch the newsletter")
        XCTAssertEqual(rows.first?.caption, "To-do")
        XCTAssertTrue(rows.allSatisfy(\.isTodo))
        XCTAssertTrue(rows.allSatisfy { !$0.isDone })
        XCTAssertEqual(rows.map(\.title), tree.openTodos().flatMap { $0.todos.map(\.text) })
    }

    func testEverythingWalksIn() {
        let tree = tree
        let top = TVFilesText.rows(.everything, in: tree)
        XCTAssertEqual(top.map(\.title), tree.children(of: rootID).map(\.text))
        let newsletter = top[0]
        XCTAssertEqual(TVFilesText.label(newsletter.tag), "4 inside · 2 open")
        let inside = TVFilesText.rows(.everything, in: tree, inside: newsletter.id)
        XCTAssertEqual(inside.first?.title, "Pick a name")
        XCTAssertEqual(inside.first?.caption, "To-do", "Inside a bud the trail is above, so the row says its kind")
        XCTAssertEqual(TVFilesText.rows(.todos, in: tree, inside: newsletter.id), inside, "A walk in from any page shows the bud's children")
        XCTAssertEqual(TVFilesText.trail(inside: inside.first!.id, in: tree), ["Launch the newsletter", "Pick a name"])
        XCTAssertEqual(TVFilesText.trail(inside: rootID, in: tree), [])
        XCTAssertEqual(TVFilesText.rows(.pinned, in: tree).map(\.title), ["Launch the newsletter"])
    }

    func testADueDateReadsOverdueOnceTheDayHasPassed() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(TVFilesText.label(.due(now.addingTimeInterval(-86_400)), now: now)!.hasPrefix("Overdue · "))
        XCTAssertTrue(TVFilesText.label(.due(now.addingTimeInterval(3_600)), now: now)!.hasPrefix("Due "))
        XCTAssertTrue(TVFilesText.label(.due(now), now: now)!.hasPrefix("Due "), "Due today is not overdue yet")
    }

    func testEveryPageHasAnEmptyLine() {
        for page in TVFilesPage.allCases {
            XCTAssertFalse(page.empty.isEmpty)
            XCTAssertTrue(TVFilesText.rows(page, in: Tree()).isEmpty)
        }
    }
}
