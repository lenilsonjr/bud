import XCTest
@testable import BudKit

final class PhysicalKeyTests: XCTestCase {
    func testTheUSKeyboardNamesEveryCodeOfTheTable() {
        let us = KeyboardLayout.us
        XCTAssertEqual(us.characters(0), "a")
        XCTAssertEqual(us.characters(40), "k")
        XCTAssertEqual(us.characters(18), "1")
        XCTAssertEqual(us.characters(44), "/")
        XCTAssertEqual(us.characters(50), "`")
        XCTAssertEqual(us.characters(10), "§", "The ISO keyboard's extra key")
        XCTAssertNil(us.characters(49), "Space is named by its code, not the table")
        XCTAssertNil(us.characters(122), "F1")
        XCTAssertNil(us.characters(51), "Delete")
        XCTAssertEqual(us.base(for: 0), .letter("a"))
        XCTAssertEqual(us.base(for: 49), .space)
        XCTAssertEqual(us.base(for: 53), .escape)
        XCTAssertEqual(us.base(for: 36), .return)
        XCTAssertEqual(us.base(for: 76), .return, "Enter on the keypad is Return")
        XCTAssertEqual(us.base(for: 48), .tab)
        XCTAssertEqual(us.base(for: 126), .upArrow)
        XCTAssertEqual(us.base(for: 125), .downArrow)
        XCTAssertNil(us.base(for: 122))
        XCTAssertNil(us.base(for: 123), "A left arrow has no name in the table")
    }

    func testAKeyboardInUseNamesTheLettersAndTheNamedKeysKeepTheirCodes() {
        let dvorak = KeyboardLayout([40: "t", 0: "a", 12: "'", 17: "y", 20: "\u{300}"])
        XCTAssertEqual(dvorak.base(for: 40), .letter("t"))
        XCTAssertEqual(dvorak.base(for: 12), .letter("'"))
        XCTAssertEqual(dvorak.base(for: 49), .space)
        XCTAssertNil(dvorak.base(for: 20), "A combining mark is no key the table can name")
        XCTAssertNil(dvorak.base(for: 1), "A code the keyboard gives nothing")
        let shifted = KeyboardLayout([0: "A"])
        XCTAssertEqual(shifted.base(for: 0), .letter("a"), "The table keeps letters small")
    }

    func testAPhysicalKeyReadsAsTheKeyboardInUseNamesItWithTheUSOneStandingIn() {
        let key = PhysicalKey(code: 40, modifiers: .option)
        XCTAssertEqual(key.key(in: .us), Key("k", .option))
        XCTAssertEqual(key.key(in: KeyboardLayout([40: "t"])), Key("t", .option))
        XCTAssertEqual(key.key(in: KeyboardLayout([:])), Key("k", .option), "The US keyboard stands in")
        XCTAssertEqual(PhysicalKey(code: 49, modifiers: [.option, .shift]).key(in: KeyboardLayout([:])), Key(.space, [.option, .shift]))
        XCTAssertNil(PhysicalKey(code: 122, modifiers: .command).key(in: .us), "F1 has no name on any keyboard")
        XCTAssertEqual(KeyboardLayout.current.characters(40), "k", "The US keyboard until the app says otherwise")
        XCTAssertEqual(key.key(), Key("k", .option))
    }

    func testAKeyOfTheTableSitsSomewhereOnTheUSKeyboard() {
        XCTAssertEqual(PhysicalKey(Key("k", .command)), PhysicalKey(code: 40, modifiers: .command))
        XCTAssertEqual(PhysicalKey(Key(.space, .option)), PhysicalKey(code: 49, modifiers: .option))
        XCTAssertEqual(PhysicalKey(Key(.return)), PhysicalKey(code: 36, modifiers: []), "Return, not Enter on the keypad")
        XCTAssertEqual(PhysicalKey(Key(.escape)), PhysicalKey(code: 53, modifiers: []))
        XCTAssertEqual(PhysicalKey(Key(.tab, .shift)), PhysicalKey(code: 48, modifiers: .shift))
        XCTAssertEqual(PhysicalKey(Key(.upArrow))?.code, 126)
        XCTAssertEqual(PhysicalKey(Key(.downArrow))?.code, 125)
        XCTAssertEqual(PhysicalKey(Key("/", .command))?.code, 44)
        XCTAssertEqual(PhysicalKey(Key("1", .command))?.code, 18)
        XCTAssertNil(PhysicalKey(Key("é", .command)), "No US key types it")
        for code in UInt16(0)...50 {
            guard let base = KeyboardLayout.us.base(for: code) else { continue }
            XCTAssertEqual(KeyboardLayout.code(for: base), code, "\(code) round trips")
        }
    }

    func testAPhysicalKeyRoundTripsThroughItsStoredForm() throws {
        let keys = [PhysicalKey(code: 40, modifiers: .option), PhysicalKey(code: 49, modifiers: [.option, .shift]), PhysicalKey(code: 0, modifiers: [.control, .command])]
        for key in keys {
            XCTAssertEqual(try JSONDecoder().decode(PhysicalKey.self, from: try JSONEncoder().encode(key)), key)
        }
        let sorted = JSONEncoder()
        sorted.outputFormatting = .sortedKeys
        XCTAssertEqual(String(data: try sorted.encode(PhysicalKey(code: 40, modifiers: .option)), encoding: .utf8), #"{"code":40,"modifiers":2}"#)
        XCTAssertThrowsError(try JSONDecoder().decode(PhysicalKey.self, from: Data(#"{"code":"k","modifiers":2}"#.utf8)))
    }
}
