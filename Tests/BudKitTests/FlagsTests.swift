import XCTest
@testable import BudKit

final class FlagEnumTests: XCTestCase {
    func testTheChoicesReadAsTheirLabels() {
        XCTAssertEqual(Appearance.allCases.map(\.rawValue), ["System", "Light", "Dark"])
        XCTAssertEqual(PhoneSplit.allCases.map(\.rawValue), ["30 / 70", "40 / 60"])
        XCTAssertEqual(PhoneSplit.thirty.share, 0.3)
        XCTAssertEqual(PhoneSplit.forty.share, 0.4)
    }
}

#if canImport(Combine)
@MainActor
final class FlagsTests: XCTestCase {
    private func freshDefaults() throws -> UserDefaults {
        let name = "bud.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testAFreshInstallHasTheDefaults() throws {
        let flags = Flags(defaults: try freshDefaults())
        XCTAssertEqual(flags.appearance, .system)
        XCTAssertEqual(flags.phoneSplit, .thirty)
    }

    func testAChoiceIsKeptAndReadBack() throws {
        let defaults = try freshDefaults()
        let flags = Flags(defaults: defaults)
        flags.appearance = .dark
        flags.phoneSplit = .forty
        let again = Flags(defaults: defaults)
        XCTAssertEqual(again.appearance, .dark)
        XCTAssertEqual(again.phoneSplit, .forty)
    }

    func testAnUnknownStoredValueFallsBackToTheDefault() throws {
        let defaults = try freshDefaults()
        defaults.set("Sepia", forKey: Flags.Key.appearance)
        XCTAssertEqual(Flags(defaults: defaults).appearance, .system)
    }
}
#endif
