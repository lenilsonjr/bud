import XCTest
@testable import BudKit

/// A bud keeps its id while the vault gives it new paths.
final class PathBookTests: XCTestCase {
    private let kitchen = UUID()
    private let shelf = UUID()
    private let oven = UUID()

    private func book() -> PathBook {
        var book = PathBook()
        book.learn(kitchen, at: "Kitchen.md")
        book.learn(shelf, at: "Kitchen/Shelf.md")
        book.learn(oven, at: "Kitchen/Shelf/Oven.md")
        return book
    }

    func testAnUnknownBudIsItsIdAndAnUnknownPathIsDerived() {
        let id = UUID()
        XCTAssertEqual(PathBook().path(of: id), id.uuidString)
        XCTAssertEqual(PathBook().id(for: "Garden.md"), Bud.id(forPath: "Garden.md"))
    }

    func testARenameCarriesTheFolderWithIt() {
        var book = book()
        book.move(from: "Kitchen.md", to: "Pantry.md")
        XCTAssertEqual(book.path(of: kitchen), "Pantry.md")
        XCTAssertEqual(book.path(of: shelf), "Pantry/Shelf.md")
        XCTAssertEqual(book.path(of: oven), "Pantry/Shelf/Oven.md")
        XCTAssertEqual(book.id(for: "Pantry/Shelf.md"), shelf)
        XCTAssertNotEqual(book.id(for: "Kitchen/Shelf.md"), shelf, "the old path names nothing now")
    }

    func testTheTrashAndBackKeepTheIds() {
        var book = book()
        book.move(from: "Kitchen/Shelf.md", to: ".trash/Kitchen/Shelf.md")
        XCTAssertEqual(book.path(of: oven), ".trash/Kitchen/Shelf/Oven.md")
        XCTAssertEqual(book.path(of: kitchen), "Kitchen.md", "a sibling folder name is not a prefix match")
        book.move(from: ".trash/Kitchen/Shelf.md", to: "Kitchen/Shelf.md")
        XCTAssertEqual(book.path(of: oven), "Kitchen/Shelf/Oven.md")
    }

    func testAFolderOnlyBudMovesItsChildren() {
        var book = PathBook()
        let trips = UUID(), rome = UUID()
        book.learn(trips, at: "Trips")
        book.learn(rome, at: "Trips/Rome.md")
        book.move(from: "Trips", to: "Archive/Trips")
        XCTAssertEqual(book.path(of: rome), "Archive/Trips/Rome.md")
    }

    func testASnapshotKeepsKnownIdsAndDropsTheRest() {
        var book = book()
        book.keep([
            BudRecord(path: "Kitchen.md", title: "Kitchen"),
            BudRecord(path: "Garden.md", title: "Garden"),
        ])
        XCTAssertEqual(book.id(for: "Kitchen.md"), kitchen)
        XCTAssertEqual(book.path(of: shelf), shelf.uuidString, "gone from the vault, gone from the book")
        XCTAssertEqual(book.id(for: "Garden.md"), Bud.id(forPath: "Garden.md"))
    }

    func testAPathTakenByAnotherBudLeavesTheFormerOwnerWithout() {
        var book = book()
        let newcomer = UUID()
        book.learn(newcomer, at: "Kitchen.md")
        XCTAssertEqual(book.id(for: "Kitchen.md"), newcomer)
        XCTAssertEqual(book.path(of: kitchen), kitchen.uuidString, "never another bud's file")
    }

    func testTrashFoldersThatStandForLiveBudsAreLeftOut() {
        let records = BudRecord.withoutTrashFolders([
            BudRecord(path: "Kitchen.md", title: "Kitchen"),
            BudRecord(path: ".trash/Kitchen", title: "Kitchen", place: .trash),
            BudRecord(path: ".trash/Kitchen/Shelf.md", parent: ".trash/Kitchen", title: "Shelf", place: .trash),
            BudRecord(path: ".trash/Inbox", title: "Inbox", place: .trash),
            BudRecord(path: ".trash/Inbox/Call.md", parent: ".trash/Inbox", title: "Call", place: .trash),
            BudRecord(path: ".trash/Old", title: "Old", place: .trash),
            BudRecord(path: ".trash/Old/Note.md", parent: ".trash/Old", title: "Note", place: .trash),
        ])
        XCTAssertEqual(records.map(\.path), [
            "Kitchen.md", ".trash/Kitchen/Shelf.md", ".trash/Inbox/Call.md", ".trash/Old", ".trash/Old/Note.md",
        ])
        XCTAssertEqual(records[1].parent, "Kitchen.md", "hangs from the live bud")
        XCTAssertNil(records[2].parent, "a capture's folder stands for the Inbox")
        XCTAssertEqual(records[4].parent, ".trash/Old", "a folder trashed on purpose stays a bud")
    }

    func testATreeFromRecordsUsesTheBookForIds() {
        var book = book()
        book.move(from: "Kitchen.md", to: "Pantry.md")
        let tree = Tree(
            records: [
                BudRecord(path: "Pantry.md", title: "Pantry"),
                BudRecord(path: "Pantry/Shelf.md", parent: "Pantry.md", title: "Shelf"),
            ],
            id: book.id(for:)
        )
        XCTAssertEqual(tree.bud(shelf)?.parent, kitchen)
        XCTAssertEqual(tree.bud(kitchen)?.text, "Pantry")
    }
}
