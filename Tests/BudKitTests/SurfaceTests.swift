import XCTest
@testable import BudKit

final class SurfaceTests: XCTestCase {
    func testTheSwitchListsTheFourViewsInTheDesignsOrder() {
        XCTAssertEqual(Surface.allCases.map(\.rawValue), ["Canvas", "Files", "Board", "Calendar"])
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

#if canImport(SwiftUI)
/// Go anywhere's destinations through the store, which exists only where SwiftUI does.
@MainActor
final class SurfaceDestinationTests: XCTestCase {
    func testGoingToEverythingFromAQuietViewLandsWhereItShows() throws {
        let store = BudStore(fileURL: nil)
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first)
        for quiet in [Surface.board, .calendar] {
            store.surface = quiet
            store.center = thread.id
            store.go(to: .everything, inFiles: false)
            XCTAssertEqual(store.surface, .canvas, "A pick from \(quiet.rawValue) is shown on the canvas")
            XCTAssertEqual(store.center, rootID)

            store.surface = quiet
            store.place = .inbox
            store.go(to: .everything, inFiles: true)
            XCTAssertEqual(store.surface, .files, "Opened in Files, it is the root's page")
            XCTAssertEqual(store.center, rootID)
            XCTAssertNil(store.place, "Not the place Files showed before")
            XCTAssertNil(store.lens)
        }
    }

    func testGoingToAPlaceOrALensFromAQuietViewOpensFiles() {
        let store = BudStore(fileURL: nil)
        let places: [Destination: Place] = [.inbox: .inbox, .archive: .archive, .trash: .trash]
        for (destination, place) in places {
            store.surface = .board
            store.go(to: destination, inFiles: false)
            XCTAssertEqual(store.surface, Surface.files, "\(destination.rawValue) is a page in Files")
            XCTAssertEqual(store.place, place, destination.rawValue)
            XCTAssertNil(store.lens, destination.rawValue)
        }
        let lenses: [Destination: Lens] = [.today: .today, .todos: .todos, .pinned: .pinned]
        for (destination, lens) in lenses {
            store.surface = .calendar
            store.go(to: destination, inFiles: false)
            XCTAssertEqual(store.surface, Surface.files, "\(destination.rawValue) is a page in Files")
            XCTAssertEqual(store.lens, lens, destination.rawValue)
            XCTAssertNil(store.place, destination.rawValue)
        }
    }
}
#endif
