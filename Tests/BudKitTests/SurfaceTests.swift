import XCTest
@testable import BudKit

final class SurfaceTests: XCTestCase {
    func testTheSwitchListsTheFourViewsInTheDesignsOrder() {
        XCTAssertEqual(Surface.allCases.map(\.rawValue), ["Canvas", "Files", "Board", "Calendar"])
    }

    func testAViewNotBuiltYetSaysSoUnderItsName() {
        XCTAssertEqual(Surface.board.comingLine, "The board view is coming.")
        XCTAssertEqual(Surface.calendar.comingLine, "The calendar view is coming.")
    }

    func testEveryViewHasAKeyOfItsOwn() {
        XCTAssertEqual(Command.of(.canvas).key, Key("1", .command))
        XCTAssertEqual(Command.of(.files).key, Key("2", .command))
        XCTAssertEqual(Command.of(.board).key, Key("3", .command))
        XCTAssertEqual(Command.of(.calendar).key, Key("4", .command))
    }
}
