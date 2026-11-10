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

    func testEveryViewResolvesToItsOwnCommandRowAndBack() {
        for view in Surface.allCases {
            let command = Command.of(view.command)
            XCTAssertEqual(command.name, view.rawValue, "The row is named after the view")
            XCTAssertEqual(command.scope, .everywhere)
            XCTAssertFalse(command.inPlace, "The store performs the switch")
            XCTAssertEqual(view.command.surface, view, "The mapping reads back")
        }
        XCTAssertEqual(Set(Surface.allCases.map(\.command)).count, Surface.allCases.count, "No two views share a row")
        XCTAssertNil(Command.ID.goAnywhere.surface)
        XCTAssertNil(Command.ID.openInFiles.surface, "Open in Files is a list's key, not the switch")
    }
}
