import XCTest
@testable import BudKit

final class FlagEnumTests: XCTestCase {
    func testTheChoicesReadAsTheirLabels() {
        XCTAssertEqual(Appearance.allCases.map(\.rawValue), ["System", "Light", "Dark"])
    }
}

#if canImport(Combine)
@MainActor
final class FlagsTests: XCTestCase {
    func testAFreshInstallHasTheDefaults() throws {
        let flags = Flags(defaults: try freshDefaults())
        XCTAssertEqual(flags.appearance, .system)
    }

    func testAChoiceIsKeptAndReadBack() throws {
        let defaults = try freshDefaults()
        let flags = Flags(defaults: defaults)
        flags.appearance = .dark
        let again = Flags(defaults: defaults)
        XCTAssertEqual(again.appearance, .dark)
    }

    func testAnUnknownStoredValueFallsBackToTheDefault() throws {
        let defaults = try freshDefaults()
        defaults.set("Sepia", forKey: Flags.Key.appearance)
        XCTAssertEqual(Flags(defaults: defaults).appearance, .system)
    }
}
#endif
