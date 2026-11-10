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
        let inPlace: Set<Command.ID> = [.undo, .rowDown, .rowUp, .choose, .openInFiles, .close, .nest, .rise, .linkAsTyped]
        for id in Command.ID.allCases {
            let command = Command.of(id)
            let (name, scope, key) = try XCTUnwrap(expected[id], "\(id) is in the table and the test")
            XCTAssertEqual(command.name, name)
            XCTAssertEqual(command.scope, scope)
            XCTAssertEqual(command.key, key)
            XCTAssertEqual(command.inPlace, inPlace.contains(id), "\(id) acts where it is bound or through the store")
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

    func testTheMenuBarListsTheRowsTheStorePerformsUnderTheScopesThatHaveOne() {
        let listed = Command.menuScopes.flatMap(Command.menu(in:))
        XCTAssertEqual(listed.map(\.id), [.goAnywhere, .capture, .canvas, .files, .newUnderThis, .open, .back, .nextMatch, .previousMatch, .soil, .closeOrReopen, .read])
        XCTAssertTrue(listed.allSatisfy { !$0.inPlace })
        XCTAssertEqual(Command.menuScopes, [.everywhere, .canvas, .document], "Files has no row of its own yet")
    }

    func testNoTwoMenuRowsShareAModifiedKeyWhateverTheirScope() {
        // A menu key equivalent is answered before any view sees the key, so a modified key can
        // stand for one row only. A bare key is no equivalent: Esc is Back on the canvas and
        // Read on a page.
        let keys = Command.menuScopes.flatMap(Command.menu(in:)).map(\.key).filter(\.hasModifiers)
        XCTAssertEqual(keys.count, Set(keys).count)
        XCTAssertEqual(keys.filter { $0 == Key(.return, .command) }.count, 1, "The page's Close or reopen alone has the key")
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
        XCTAssertTrue(store.perform(.open, on: bud))
        XCTAssertEqual(store.lastCommand?.command, .open)
        XCTAssertEqual(store.lastCommand?.bud, bud)
        XCTAssertFalse(store.perform(.read), "A document command waits for a page")
        store.openAsFile(bud)
        XCTAssertTrue(store.allows(.read))
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

    func testEveryMenuRowRunsThroughTheStoreAndEveryInPlaceRowIsLeftToItsControl() throws {
        let (store, bud) = store()
        let todo = try XCTUnwrap(store.add("Water the ferns", todo: true, under: bud))
        for command in Command.all {
            store.modal = nil
            if command.scope == .document { store.openAsFile(todo.id) } else { store.surface = .canvas }
            XCTAssertEqual(store.perform(command.id, on: bud), !command.inPlace, "\(command.id)")
        }
        store.modal = nil
        store.surface = .canvas
        XCTAssertEqual(store.lastCommand?.command, Command.all.last { !$0.inPlace }?.id)
    }

    func testACardOverTheWindowTakesEveryKey() {
        let (store, bud) = store()
        store.modal = .capture
        XCTAssertFalse(store.allows(.goAnywhere))
        XCTAssertFalse(store.allows(.back))
        XCTAssertFalse(store.perform(.newUnderThis, on: bud))
        XCTAssertNil(store.lastCommand)
        store.modal = nil
        XCTAssertTrue(store.allows(.goAnywhere))
    }

    func testOpenNeedsTheLitCard() {
        let (store, bud) = store()
        XCTAssertTrue(store.allows(.open), "The menu lists Open on the canvas")
        XCTAssertFalse(store.perform(.open), "Space with nothing lit goes on")
        XCTAssertNil(store.lastCommand)
        XCTAssertTrue(store.perform(.open, on: bud))
        XCTAssertEqual(store.lastCommand?.bud, bud)
    }

    func testCloseOrReopenNeedsAToDosPage() throws {
        let (store, bud) = store()
        let note = try XCTUnwrap(store.add("A thought", todo: false, under: bud))
        store.openAsFile(note.id)
        XCTAssertTrue(store.allows(.read))
        XCTAssertFalse(store.allows(.closeOrReopen))
        XCTAssertFalse(store.perform(.closeOrReopen))
        let todo = try XCTUnwrap(store.add("Water the ferns", todo: true, under: bud))
        store.openAsFile(todo.id)
        XCTAssertTrue(store.allows(.closeOrReopen))
    }

    func testThePageIsABudsOwnInFilesAndNothingElse() {
        let (store, bud) = store()
        XCTAssertNil(store.page, "The canvas has no page")
        store.openAsFile(bud)
        XCTAssertEqual(store.page, bud)
        store.openAsFile(rootID)
        XCTAssertNil(store.page, "Everything is no bud's page")
        store.openInbox()
        XCTAssertNil(store.page)
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
