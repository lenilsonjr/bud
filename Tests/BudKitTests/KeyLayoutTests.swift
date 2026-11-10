import XCTest
@testable import BudKit

final class KeyLayoutTests: XCTestCase {
    private func freshDefaults() throws -> UserDefaults {
        let name = "bud.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func layout() throws -> KeyLayout { KeyLayout(defaults: try freshDefaults()) }

    func testAFreshLayoutReadsTheTablesDefaults() throws {
        let layout = try layout()
        for command in Command.all {
            XCTAssertEqual(layout.key(for: command.id), command.key)
            XCTAssertFalse(layout.isChanged(command.id))
        }
        XCTAssertEqual(layout.changed, 0)
        XCTAssertNil(layout.recording)
        XCTAssertNil(layout.conflict)
    }

    func testAClickOnAKeycapRecordsTheNextKeyForTheRow() throws {
        let layout = try layout()
        layout.startRecording(.goAnywhere)
        XCTAssertEqual(layout.recording, .goAnywhere)
        XCTAssertEqual(layout.record(Key("p", .command)), .bound)
        XCTAssertNil(layout.recording, "One key ends the recording")
        XCTAssertEqual(layout.key(for: .goAnywhere), Key("p", .command))
        XCTAssertTrue(layout.isChanged(.goAnywhere))
        XCTAssertEqual(layout.changed, 1)
        XCTAssertEqual(layout.overrides, [.goAnywhere: Key("p", .command)])
        XCTAssertEqual(layout.key(for: .capture), Key(.space, .option), "The other rows keep theirs")
    }

    func testEscCancelsAndTheRowKeepsItsKey() throws {
        let layout = try layout()
        layout.startRecording(.soil)
        XCTAssertEqual(layout.record(Key(.escape)), .cancelled)
        XCTAssertNil(layout.recording)
        XCTAssertEqual(layout.key(for: .soil), Key("j", .command))
        XCTAssertEqual(layout.changed, 0)
        layout.startRecording(.soil)
        layout.cancelRecording()
        XCTAssertNil(layout.recording)
        XCTAssertEqual(layout.record(Key("l", .command)), .cancelled, "A key with no row recording lands nowhere")
        XCTAssertEqual(layout.changed, 0)
    }

    func testABareKeyIsRefusedForARowThatFiresEverywhereAndTheRowKeepsRecording() throws {
        let layout = try layout()
        layout.startRecording(.goAnywhere)
        XCTAssertEqual(layout.record(Key("p")), .refused)
        XCTAssertEqual(layout.recording, .goAnywhere, "The row waits for a better key")
        XCTAssertTrue(layout.refused, "The row says why until the next key")
        XCTAssertEqual(layout.record(Key("p", .shift)), .refused, "Shift alone types a capital")
        XCTAssertEqual(layout.record(Key(.return)), .refused)
        XCTAssertEqual(layout.key(for: .goAnywhere), Key("k", .command))
        XCTAssertEqual(layout.record(Key("p", .command)), .bound)
        XCTAssertFalse(layout.refused)
        layout.startRecording(.open)
        XCTAssertEqual(layout.record(Key("o")), .bound, "A row of one surface may take a bare key, as Space is Open")
        XCTAssertEqual(layout.key(for: .open), Key("o"))
    }

    func testAKeyAnotherRowHoldsShowsOnBothRowsAndIsNotSavedUntilOneChanges() throws {
        let defaults = try freshDefaults()
        let layout = KeyLayout(defaults: defaults)
        layout.startRecording(.goAnywhere)
        XCTAssertEqual(layout.record(Key("j", .command)), .taken(by: .soil))
        XCTAssertNil(layout.recording)
        XCTAssertEqual(layout.conflict, KeyLayout.Conflict(id: .goAnywhere, key: Key("j", .command), holder: .soil))
        XCTAssertEqual(layout.key(for: .goAnywhere), Key("k", .command), "The wanted key is not the row's yet")
        XCTAssertEqual(layout.key(for: .soil), Key("j", .command))
        XCTAssertEqual(layout.changed, 0)
        XCTAssertEqual(KeyLayout(defaults: defaults).changed, 0, "Nothing was saved")
        layout.startRecording(.soil)
        XCTAssertEqual(layout.record(Key("l", .command)), .bound)
        XCTAssertNil(layout.conflict, "The holder moved off the key, so the wanted key lands")
        XCTAssertEqual(layout.key(for: .goAnywhere), Key("j", .command))
        XCTAssertEqual(layout.key(for: .soil), Key("l", .command))
        XCTAssertEqual(layout.changed, 2)
        XCTAssertEqual(KeyLayout(defaults: defaults).overrides, layout.overrides)
    }

    func testTheRowThatWantsAKeyCanRecordAnotherOrLetGoInstead() throws {
        let layout = try layout()
        layout.startRecording(.goAnywhere)
        layout.record(Key("j", .command))
        layout.startRecording(.goAnywhere)
        XCTAssertEqual(layout.record(Key("p", .command)), .bound)
        XCTAssertNil(layout.conflict, "Another key for the row drops what it wanted")
        layout.startRecording(.goAnywhere)
        layout.record(Key("j", .command))
        XCTAssertNotNil(layout.conflict)
        layout.startRecording(.goAnywhere)
        XCTAssertEqual(layout.record(Key("p", .command)), .bound, "Its own key again keeps it and drops the wish")
        XCTAssertNil(layout.conflict)
        layout.startRecording(.goAnywhere)
        layout.record(Key("j", .command))
        layout.reset(.goAnywhere)
        XCTAssertNil(layout.conflict, "Reset on the row that wants lets go of the key")
        XCTAssertEqual(layout.key(for: .goAnywhere), Key("k", .command))
    }

    func testARowClashesWithAnotherInItsScopeOrAcrossScopesWhereBothWouldFire() throws {
        let layout = try layout()
        layout.startRecording(.open)
        XCTAssertEqual(layout.record(Key("k", .command)), .taken(by: .goAnywhere), "A modified key stands once in the menu bar")
        layout.startRecording(.read)
        XCTAssertEqual(layout.record(Key("n")), .taken(by: .newUnderThis), "A row that fires everywhere answers on a page too")
        layout.startRecording(.read)
        XCTAssertEqual(layout.record(Key(.space)), .bound, "Open is the canvas's, a page never sees it")
        layout.startRecording(.back)
        XCTAssertEqual(layout.record(Key(.tab)), .taken(by: .nest), "Add inside the last one has Tab on the canvas already")
        XCTAssertEqual(layout.conflict?.holder, .nest)
        layout.startRecording(.nest)
        XCTAssertEqual(layout.record(Key(.return)), .bound, "Choose is a list's own, in place")
        XCTAssertNil(layout.conflict, "Tab is free now, so Back takes it")
        XCTAssertEqual(layout.key(for: .back), Key(.tab))
        XCTAssertNil(layout.holder(of: Key("q", .command), besides: .soil))
        XCTAssertEqual(layout.holder(of: Key("g", [.command, .shift]), besides: .soil), .previousMatch)
    }

    func testResetPutsTheDefaultBackAndResetAllClearsEveryChange() throws {
        let defaults = try freshDefaults()
        let layout = KeyLayout(defaults: defaults)
        layout.startRecording(.goAnywhere)
        layout.record(Key("p", .command))
        layout.startRecording(.soil)
        layout.record(Key("l", .command))
        XCTAssertEqual(layout.changed, 2)
        layout.reset(.goAnywhere)
        XCTAssertEqual(layout.key(for: .goAnywhere), Key("k", .command))
        XCTAssertFalse(layout.isChanged(.goAnywhere))
        XCTAssertEqual(layout.changed, 1)
        layout.startRecording(.capture)
        layout.record(Key("l", .command))
        XCTAssertNotNil(layout.conflict)
        layout.startRecording(.read)
        layout.resetAll()
        XCTAssertEqual(layout.changed, 0)
        XCTAssertNil(layout.conflict)
        XCTAssertNil(layout.recording)
        XCTAssertEqual(KeyLayout(defaults: defaults).changed, 0)
        for command in Command.all {
            XCTAssertEqual(layout.key(for: command.id), command.key)
        }
    }

    func testRecordingTheDefaultAgainDropsTheChange() throws {
        let layout = try layout()
        layout.startRecording(.goAnywhere)
        layout.record(Key("p", .command))
        layout.startRecording(.goAnywhere)
        XCTAssertEqual(layout.record(Key("k", .command)), .bound)
        XCTAssertFalse(layout.isChanged(.goAnywhere))
        XCTAssertEqual(layout.changed, 0)
    }

    func testAResetHolderLetsAWantedKeyLandOnlyWhenItMovesOff() throws {
        let layout = try layout()
        layout.startRecording(.soil)
        layout.record(Key("l", .command))
        layout.startRecording(.goAnywhere)
        XCTAssertEqual(layout.record(Key("l", .command)), .taken(by: .soil))
        layout.reset(.soil)
        XCTAssertNil(layout.conflict, "Soil went back to its default, so the key is free")
        XCTAssertEqual(layout.key(for: .goAnywhere), Key("l", .command))
        XCTAssertEqual(layout.key(for: .soil), Key("j", .command))
    }

    func testTheChangesSurviveARelaunchOnTheSameDevice() throws {
        let defaults = try freshDefaults()
        let layout = KeyLayout(defaults: defaults)
        layout.startRecording(.goAnywhere)
        layout.record(Key("p", .command))
        layout.startRecording(.nest)
        layout.record(Key(.return))
        let again = KeyLayout(defaults: defaults)
        XCTAssertEqual(again.key(for: .goAnywhere), Key("p", .command))
        XCTAssertEqual(again.key(for: .nest), Key(.return))
        XCTAssertEqual(again.changed, 2)
        XCTAssertNil(again.recording, "A recording is not kept")
        XCTAssertNil(again.conflict, "Nor a key that never landed")
        XCTAssertEqual(KeyLayout(defaults: try freshDefaults()).changed, 0, "Another device has its own")
    }

    func testTheAppsKeysReadThroughTheLayoutOnThisDevice() {
        for command in Command.all {
            XCTAssertEqual(Keys.key(for: command.id), Keys.layout.key(for: command.id))
        }
    }

    func testAKeyRoundTripsThroughItsStoredForm() throws {
        let keys = [Key("k", .command), Key(.space, .option), Key("g", [.command, .shift]), Key(.escape), Key(.tab, [.shift, .control]), Key(.upArrow), Key(.downArrow), Key(.return, .command), Key("/", .command)]
        for key in keys {
            let data = try JSONEncoder().encode(key)
            XCTAssertEqual(try JSONDecoder().decode(Key.self, from: data), key)
        }
        let sorted = JSONEncoder()
        sorted.outputFormatting = .sortedKeys
        XCTAssertEqual(String(data: try sorted.encode(Key("k", .command)), encoding: .utf8), #"{"base":"k","modifiers":8}"#)
        XCTAssertThrowsError(try JSONDecoder().decode(Key.self, from: Data(#"{"base":"delete","modifiers":0}"#.utf8)))
    }

    func testWhatTheStoreCannotReadLeavesTheDefaults() throws {
        let defaults = try freshDefaults()
        defaults.set(Data("not keys".utf8), forKey: KeyLayout.key)
        XCTAssertEqual(KeyLayout(defaults: defaults).changed, 0)
        defaults.set(Data(#"{"goAnywhere":{"base":"p","modifiers":8},"gone":{"base":"q","modifiers":8}}"#.utf8), forKey: KeyLayout.key)
        let layout = KeyLayout(defaults: defaults)
        XCTAssertEqual(layout.overrides, [.goAnywhere: Key("p", .command)], "A row that is no longer in the table is dropped")
    }
}
