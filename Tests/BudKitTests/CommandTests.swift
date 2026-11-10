import XCTest
@testable import BudKit

final class CommandTests: XCTestCase {
    func testTheTableHoldsEveryKeyTheAppAnswersTo() throws {
        XCTAssertEqual(Command.all.map(\.id), Command.ID.allCases, "Every id has one row, in the table's order")
        let expected: [Command.ID: (String, Command.Scope, Key)] = [
            .goAnywhere: ("Go anywhere", .everywhere, Key("k", .command)),
            .capture: ("Capture", .everywhere, Key(.space, .option)),
            .undo: ("Undo", .everywhere, Key("z", .command)),
            .canvas: ("Canvas", .everywhere, Key("1", .command)),
            .files: ("Files", .everywhere, Key("2", .command)),
            .newUnderThis: ("New under this", .everywhere, Key("n")),
            .rowDown: ("Next row", .everywhere, Key(.downArrow)),
            .rowUp: ("Previous row", .everywhere, Key(.upArrow)),
            .choose: ("Choose", .everywhere, Key(.return)),
            .openInFiles: ("Open in Files", .everywhere, Key(.return, .command)),
            .close: ("Close", .everywhere, Key(.escape)),
            .open: ("Open", .canvas, Key(.space)),
            .back: ("Back", .canvas, Key(.escape)),
            .nextMatch: ("Next match", .canvas, Key("g", .command)),
            .previousMatch: ("Previous match", .canvas, Key("g", [.command, .shift])),
            .soil: ("Soil", .canvas, Key("j", .command)),
            .nest: ("Add inside the last one", .canvas, Key(.tab)),
            .rise: ("Back up a level", .canvas, Key(.tab, .shift)),
            .closeOrReopen: ("Close or reopen", .document, Key(.return, .command)),
            .read: ("Read", .document, Key(.escape)),
            .linkAsTyped: ("Link as typed", .document, Key(.tab)),
        ]
        for id in Command.ID.allCases {
            let command = Command.of(id)
            let (name, scope, key) = try XCTUnwrap(expected[id], "\(id) is in the table and the test")
            XCTAssertEqual(command.name, name)
            XCTAssertEqual(command.scope, scope)
            XCTAssertEqual(command.key, key)
            XCTAssertEqual(Keys.key(for: id), key, "The binding reads the default until a user layer comes")
        }
    }

    func testNoTwoCommandsInTheSameScopeShareAKey() {
        for scope in Command.Scope.allCases {
            let keys = Command.all(in: scope).map(\.key)
            XCTAssertEqual(keys.count, Set(keys).count, "\(scope) binds each key once")
        }
    }

    func testEachScopeListsItsCommandsInTheTablesOrder() {
        XCTAssertEqual(Command.all(in: .canvas).map(\.id), [.open, .back, .nextMatch, .previousMatch, .soil, .nest, .rise])
        XCTAssertEqual(Command.all(in: .files), [])
        XCTAssertEqual(Command.all(in: .document).map(\.id), [.closeOrReopen, .read, .linkAsTyped])
        XCTAssertEqual(Command.Scope.allCases.flatMap(Command.all(in:)).count, Command.all.count)
    }

    func testTheMenuBarListsEveryRowButUndo() {
        let listed = Command.Scope.allCases.flatMap(Command.menu(in:)).map(\.id)
        XCTAssertFalse(listed.contains(.undo))
        XCTAssertEqual(listed.count, Command.all.count - 1)
        XCTAssertEqual(Command.menu(in: .canvas), Command.all(in: .canvas))
    }

    func testAKeyDrawsItselfTheWayTheBoardDoes() {
        XCTAssertEqual(Key("k", .command).label, "⌘K")
        XCTAssertEqual(Key("g", [.command, .shift]).label, "⇧⌘G")
        XCTAssertEqual(Key(.space, .option).label, "⌥Space")
        XCTAssertEqual(Key(.escape).label, "Esc")
        XCTAssertEqual(Key(.return, .command).label, "⌘↩")
        XCTAssertEqual(Key(.tab, [.shift, .control]).label, "⌃⇧⇥")
        XCTAssertEqual(Key(.upArrow).label + Key(.downArrow).label, "↑↓")
    }

    func testOnlyAModifiedKeyCanStandInTheMenuBar() {
        XCTAssertTrue(Key("k", .command).hasModifiers)
        XCTAssertFalse(Key("n").hasModifiers)
        XCTAssertFalse(Key(.escape).hasModifiers)
    }
}

#if canImport(SwiftUI)
@MainActor
final class CommandStoreTests: XCTestCase {
    private func store() -> (BudStore, UUID) {
        let store = BudStore(fileURL: nil)
        let bud = store.tree.children(of: rootID).first { store.tree.hasChildren($0.id) }!.id
        return (store, bud)
    }

    func testACanvasCommandDoesNotFireInFilesNorADocumentCommandOnTheCanvas() {
        let (store, bud) = store()
        store.surface = .files
        XCTAssertFalse(store.allows(.open))
        XCTAssertFalse(store.perform(.open))
        XCTAssertNil(store.lastCommand)
        store.surface = .canvas
        XCTAssertTrue(store.perform(.open))
        XCTAssertEqual(store.lastCommand?.command, .open)
        XCTAssertFalse(store.perform(.closeOrReopen), "A document command waits for a page")
        store.openAsFile(bud)
        XCTAssertTrue(store.allows(.closeOrReopen))
        XCTAssertTrue(store.perform(.read))
        XCTAssertEqual(store.lastCommand?.command, .read)
    }

    func testADocumentCommandNeedsABudsPageNotAPlaceOrEverything() {
        let (store, bud) = store()
        store.openInbox()
        XCTAssertFalse(store.allows(.read))
        store.open(.today)
        XCTAssertFalse(store.allows(.read))
        store.openAsFile(rootID)
        XCTAssertFalse(store.allows(.read))
        store.openAsFile(bud)
        XCTAssertTrue(store.allows(.read))
    }

    func testNewUnderThisWorksUnderTheLitCardAndUnderThePageInFiles() {
        let (store, bud) = store()
        let lit = store.tree.children(of: bud).first!.id
        XCTAssertTrue(store.perform(.newUnderThis, on: lit))
        XCTAssertEqual(store.modal, .add(parent: lit))
        store.modal = nil
        store.openAsFile(bud)
        XCTAssertTrue(store.perform(.newUnderThis))
        XCTAssertEqual(store.modal, .add(parent: bud))
    }

    func testNewUnderThisIsRefusedInFilesWithoutABudsPage() {
        let (store, bud) = store()
        store.openInbox()
        XCTAssertFalse(store.allows(.newUnderThis))
        XCTAssertFalse(store.perform(.newUnderThis))
        store.open(.today)
        XCTAssertFalse(store.perform(.newUnderThis))
        store.openAsFile(rootID)
        XCTAssertFalse(store.perform(.newUnderThis))
        XCTAssertNil(store.modal)
        XCTAssertNil(store.lastCommand)
        store.surface = .canvas
        XCTAssertTrue(store.allows(.newUnderThis), "The canvas always has a target: the lit card or the center")
        XCTAssertTrue(store.perform(.newUnderThis, on: bud))
        XCTAssertEqual(store.modal, .add(parent: bud))
    }

    func testTheSameCommandTwiceIsTwoChanges() {
        let (store, _) = store()
        store.perform(.back)
        let first = store.lastCommand
        store.perform(.back)
        XCTAssertNotEqual(store.lastCommand, first)
        XCTAssertEqual(store.lastCommand?.command, .back)
    }

    func testTheWindowsCommandsOpenGoAnywhereAndSwitchTheSurface() {
        let (store, _) = store()
        XCTAssertFalse(store.searching)
        store.perform(.goAnywhere)
        XCTAssertTrue(store.searching)
        store.perform(.files)
        XCTAssertEqual(store.surface, .files)
        store.perform(.canvas)
        XCTAssertEqual(store.surface, .canvas)
        store.perform(.capture)
        XCTAssertEqual(store.modal, .capture)
    }

    func testCloseOrReopenTicksThePage() throws {
        let (store, parent) = store()
        let todo = try XCTUnwrap(store.add("Water the ferns", todo: true, under: parent))
        store.openAsFile(todo.id)
        XCTAssertTrue(store.perform(.closeOrReopen))
        XCTAssertTrue(store.tree.bud(todo.id)?.isDone ?? false)
        XCTAssertTrue(store.perform(.closeOrReopen))
        XCTAssertFalse(store.tree.bud(todo.id)?.isDone ?? true)
    }
}
#endif
