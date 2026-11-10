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

    private func stored(_ json: String, in defaults: UserDefaults) {
        defaults.set(Data(json.utf8), forKey: KeyLayout.key)
    }

    func testAFreshLayoutReadsTheTablesDefaults() throws {
        let layout = try layout()
        for command in Command.all {
            XCTAssertEqual(layout.key(for: command.id), command.key)
            XCTAssertFalse(layout.isChanged(command.id))
        }
        XCTAssertEqual(layout.changed, 0)
        XCTAssertNil(layout.recording)
        XCTAssertEqual(layout.conflicts, [:])
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

    func testEscIsAKeyLikeAnyOtherForTheRowItIsTheDefaultOf() throws {
        let layout = try layout()
        layout.startRecording(.back)
        XCTAssertEqual(layout.record(Key(.tab, .command)), .bound)
        layout.startRecording(.back)
        XCTAssertEqual(layout.record(Key(.escape)), .bound, "Back's default is Esc, so Esc is recorded, not a cancel")
        XCTAssertFalse(layout.isChanged(.back))
        layout.startRecording(.back)
        XCTAssertEqual(layout.record(Key(.escape)), .bound, "The key the row has now binds at once")
        XCTAssertNil(layout.recording)
    }

    func testABareKeyIsRefusedForARowThatFiresEverywhereAndTheRowKeepsRecording() throws {
        let layout = try layout()
        layout.startRecording(.goAnywhere)
        XCTAssertEqual(layout.record(Key("p")), .refused)
        XCTAssertEqual(layout.recording, .goAnywhere, "The row waits for a better key")
        XCTAssertEqual(layout.refusal, .bare, "The row says why until the next key")
        XCTAssertEqual(layout.record(Key("p", .shift)), .refused, "Shift alone types a capital")
        XCTAssertEqual(layout.record(Key(.return)), .refused)
        XCTAssertEqual(layout.key(for: .goAnywhere), Key("k", .command))
        XCTAssertEqual(layout.record(Key("p", .command)), .bound)
        XCTAssertNil(layout.refusal)
        layout.startRecording(.open)
        XCTAssertEqual(layout.record(Key("o", .shift)), .bound, "A row of one surface may take a bare key, as Space is Open")
        XCTAssertEqual(layout.key(for: .open), Key("o", .shift))
        XCTAssertFalse(layout.key(for: .open).hasModifiers, "Such a key never stands in the menu bar")
    }

    func testARowThatFiresEverywhereRecordsItsBareDefaultAgainToDropTheChange() throws {
        let layout = try layout()
        layout.startRecording(.newUnderThis)
        XCTAssertEqual(layout.record(Key("n", .command)), .bound)
        XCTAssertTrue(layout.isChanged(.newUnderThis))
        layout.startRecording(.newUnderThis)
        XCTAssertEqual(layout.record(Key("n")), .bound, "The default is no bare key to refuse")
        XCTAssertFalse(layout.isChanged(.newUnderThis))
        XCTAssertEqual(layout.changed, 0)
    }

    func testAKeyTheTableCannotNameIsRefusedAndSaidSo() throws {
        let layout = try layout()
        layout.startRecording(.soil)
        XCTAssertEqual(layout.record(nil), .refused)
        XCTAssertEqual(layout.refusal, .unnamed)
        XCTAssertEqual(layout.recording, .soil)
        layout.clearRefusal()
        XCTAssertNil(layout.refusal, "The line goes after a beat, the row still recording")
        XCTAssertEqual(layout.recording, .soil)
        XCTAssertEqual(layout.record(Key("l", .command)), .bound)
        XCTAssertNil(layout.refusal)
    }

    func testTheKeysTheMacAnswersToFromTheDesktopCannotBeRecordedYet() throws {
        let layout = try layout()
        for id in Command.systemWide {
            XCTAssertFalse(layout.canRecord(id))
            layout.startRecording(id)
            XCTAssertNil(layout.recording, "\(id) is registered once at launch")
        }
        XCTAssertTrue(layout.canRecord(.goAnywhere))
        layout.startRecording(.goAnywhere)
        XCTAssertEqual(layout.recording, .goAnywhere)
    }

    func testAKeyAnotherRowHoldsShowsOnBothRowsAndIsNotSavedUntilOneChanges() throws {
        let defaults = try freshDefaults()
        let layout = KeyLayout(defaults: defaults)
        layout.startRecording(.goAnywhere)
        XCTAssertEqual(layout.record(Key("j", .command)), .taken(by: .soil))
        XCTAssertNil(layout.recording)
        let conflict = KeyLayout.Conflict(id: .goAnywhere, key: Key("j", .command), holder: .soil)
        XCTAssertEqual(layout.conflicts, [.goAnywhere: conflict])
        XCTAssertEqual(layout.wanted(.soil), conflict, "The holder's row shows it too")
        XCTAssertNil(layout.wanted(.goAnywhere))
        XCTAssertEqual(layout.key(for: .goAnywhere), Key("k", .command), "The wanted key is not the row's yet")
        XCTAssertEqual(layout.key(for: .soil), Key("j", .command))
        XCTAssertEqual(layout.changed, 0)
        XCTAssertEqual(KeyLayout(defaults: defaults).changed, 0, "Nothing was saved")
        layout.startRecording(.soil)
        XCTAssertEqual(layout.record(Key("l", .command)), .bound)
        XCTAssertEqual(layout.conflicts, [:], "The holder moved off the key, so the wanted key lands")
        XCTAssertEqual(layout.key(for: .goAnywhere), Key("j", .command))
        XCTAssertEqual(layout.key(for: .soil), Key("l", .command))
        XCTAssertEqual(layout.changed, 2)
        XCTAssertEqual(KeyLayout(defaults: defaults).overrides, layout.overrides)
    }

    func testEveryRowKeepsItsOwnConflict() throws {
        let layout = try layout()
        layout.startRecording(.goAnywhere)
        XCTAssertEqual(layout.record(Key("j", .command)), .taken(by: .soil))
        layout.startRecording(.canvas)
        XCTAssertEqual(layout.record(Key("j", .command)), .taken(by: .soil), "A second row may want the same key")
        layout.startRecording(.files)
        XCTAssertEqual(layout.record(Key("g", .command)), .taken(by: .nextMatch))
        XCTAssertEqual(layout.conflicts.count, 3)
        XCTAssertEqual(layout.wanted(.soil)?.id, .goAnywhere, "The first row in the table's order names the holder's line")
        layout.startRecording(.soil)
        layout.record(Key("l", .command))
        XCTAssertEqual(layout.key(for: .goAnywhere), Key("j", .command), "The first wanter lands")
        XCTAssertEqual(layout.conflicts[.canvas], KeyLayout.Conflict(id: .canvas, key: Key("j", .command), holder: .goAnywhere), "The second now waits on it")
        XCTAssertEqual(layout.conflicts[.files]?.holder, .nextMatch)
        layout.startRecording(.nextMatch)
        layout.record(Key("m", .command))
        XCTAssertEqual(layout.key(for: .files), Key("g", .command))
        XCTAssertEqual(layout.conflicts.keys.sorted { $0.rawValue < $1.rawValue }, [.canvas])
    }

    func testTheRowThatWantsAKeyCanRecordAnotherOrLetGoInstead() throws {
        let layout = try layout()
        layout.startRecording(.goAnywhere)
        layout.record(Key("j", .command))
        layout.startRecording(.goAnywhere)
        XCTAssertEqual(layout.record(Key("p", .command)), .bound)
        XCTAssertEqual(layout.conflicts, [:], "Another key for the row drops what it wanted")
        layout.startRecording(.goAnywhere)
        layout.record(Key("j", .command))
        XCTAssertNotNil(layout.conflicts[.goAnywhere])
        layout.startRecording(.goAnywhere)
        XCTAssertEqual(layout.record(Key("p", .command)), .bound, "Its own key again keeps it and drops the wish")
        XCTAssertEqual(layout.conflicts, [:])
        layout.startRecording(.goAnywhere)
        layout.record(Key("j", .command))
        layout.reset(.goAnywhere)
        XCTAssertEqual(layout.conflicts, [:], "Reset on the row that wants lets go of the key")
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
        XCTAssertEqual(layout.conflicts[.back]?.holder, .nest)
        layout.startRecording(.nest)
        XCTAssertEqual(layout.record(Key(.return)), .bound, "Choose is a list's own, in place")
        XCTAssertNil(layout.conflicts[.back], "Tab is free now, so Back takes it")
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
        XCTAssertEqual(layout.record(Key("l", .command)), .cancelled, "Capture is heard from the desktop, so it did not start recording")
        layout.startRecording(.canvas)
        layout.record(Key("l", .command))
        XCTAssertEqual(layout.conflicts.count, 1)
        layout.startRecording(.read)
        layout.resetAll()
        XCTAssertEqual(layout.changed, 0)
        XCTAssertEqual(layout.conflicts, [:])
        XCTAssertNil(layout.recording)
        XCTAssertEqual(KeyLayout(defaults: defaults).changed, 0)
        for command in Command.all {
            XCTAssertEqual(layout.key(for: command.id), command.key)
        }
    }

    func testResetIsAConflictWhenAChangedRowHoldsTheDefault() throws {
        let layout = try layout()
        layout.startRecording(.soil)
        layout.record(Key("l", .command))
        layout.startRecording(.nextMatch)
        XCTAssertEqual(layout.record(Key("j", .command)), .bound, "Soil's old key is free")
        layout.reset(.soil)
        XCTAssertEqual(layout.conflicts[.soil], KeyLayout.Conflict(id: .soil, key: Key("j", .command), holder: .nextMatch))
        XCTAssertEqual(layout.key(for: .soil), Key("l", .command), "Soil keeps its key until Next match moves")
        layout.reset(.nextMatch)
        XCTAssertEqual(layout.conflicts, [:])
        XCTAssertEqual(layout.key(for: .soil), Key("j", .command))
        XCTAssertEqual(layout.changed, 0)
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
        XCTAssertEqual(layout.conflicts, [:], "Soil went back to its default, so the key is free")
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
        XCTAssertEqual(again.conflicts, [:], "Nor a key that never landed")
        XCTAssertEqual(KeyLayout(defaults: try freshDefaults()).changed, 0, "Another device has its own")
    }

    func testAStoredKeyTheTableOfTodayWouldRefuseIsLetGoOnLoad() throws {
        let defaults = try freshDefaults()
        stored(#"""
            {"goAnywhere":{"base":"j","modifiers":8},
             "files":{"base":"f","modifiers":0},
             "capture":{"base":"c","modifiers":8},
             "soil":{"base":"j","modifiers":8},
             "open":{"base":"o","modifiers":0},
             "read":{"base":"o","modifiers":0}}
            """#, in: defaults)
        let layout = KeyLayout(defaults: defaults)
        XCTAssertNil(layout.overrides[.goAnywhere], "Soil has ⌘J by default")
        XCTAssertNil(layout.overrides[.files], "A bare key would type")
        XCTAssertNil(layout.overrides[.capture], "The desktop's keys cannot be recorded yet")
        XCTAssertNil(layout.overrides[.soil], "Its own default is no change")
        XCTAssertEqual(layout.overrides[.open], Key("o"))
        XCTAssertEqual(layout.overrides[.read], Key("o"), "A page and the canvas never share a bare key")
        XCTAssertEqual(layout.changed, 2)
        XCTAssertEqual(layout.conflicts, [:], "Nothing is said; the rows show their defaults")
        XCTAssertEqual(KeyLayout(defaults: defaults).changed, 2, "What was let go is gone for good")
        stored(#"{"files":{"base":"m","modifiers":8},"nextMatch":{"base":"m","modifiers":8}}"#, in: defaults)
        XCTAssertEqual(KeyLayout(defaults: defaults).overrides, [.nextMatch: Key("m", .command)], "Two stored keys alike: the first in the table's order is let go")
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
        stored("not keys", in: defaults)
        XCTAssertEqual(KeyLayout(defaults: defaults).changed, 0)
        stored(#"{"goAnywhere":{"base":"p","modifiers":8},"gone":{"base":"q","modifiers":8}}"#, in: defaults)
        let layout = KeyLayout(defaults: defaults)
        XCTAssertEqual(layout.overrides, [.goAnywhere: Key("p", .command)], "A row that is no longer in the table is dropped")
    }

    func testAMacKeyEventIsNamedByItsCodeOrItsCharactersWithTheModifiersIgnored() {
        XCTAssertEqual(Key(characters: "a", keyCode: 0, modifiers: .option), Key("a", .option), "Not the å Option made of it")
        XCTAssertEqual(Key(characters: "n", keyCode: 45, modifiers: [.option, .command]), Key("n", [.option, .command]), "A dead key is a letter still")
        XCTAssertEqual(Key(characters: "A", keyCode: 0, modifiers: .shift), Key("a", .shift))
        XCTAssertEqual(Key(characters: "/", keyCode: 44, modifiers: .command), Key("/", .command))
        XCTAssertEqual(Key(characters: "1", keyCode: 18, modifiers: .command), Key("1", .command))
        XCTAssertEqual(Key(characters: " ", keyCode: 49, modifiers: .option), Key(.space, .option))
        XCTAssertEqual(Key(characters: "\u{1B}", keyCode: 53, modifiers: []), Key(.escape))
        XCTAssertEqual(Key(characters: "\r", keyCode: 36, modifiers: .command), Key(.return, .command))
        XCTAssertEqual(Key(characters: "\u{3}", keyCode: 76, modifiers: []), Key(.return), "Enter on the keypad is Return")
        XCTAssertEqual(Key(characters: "\t", keyCode: 48, modifiers: .shift), Key(.tab, .shift))
        XCTAssertEqual(Key(characters: "\u{F700}", keyCode: 126, modifiers: []), Key(.upArrow))
        XCTAssertEqual(Key(characters: "\u{F701}", keyCode: 125, modifiers: []), Key(.downArrow))
        XCTAssertNil(Key(characters: "\u{7F}", keyCode: 51, modifiers: []), "Delete")
        XCTAssertNil(Key(characters: "\u{F704}", keyCode: 122, modifiers: []), "F1")
        XCTAssertNil(Key(characters: "\u{F729}", keyCode: 115, modifiers: []), "Home")
        XCTAssertNil(Key(characters: "\u{F702}", keyCode: 123, modifiers: []), "A left arrow")
        XCTAssertNil(Key(characters: "", keyCode: 55, modifiers: .command), "A modifier alone")
    }
}
