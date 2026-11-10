import XCTest
@testable import BudKit

extension XCTestCase {
    /// A defaults suite of this test's own: named for it alone, empty, and removed again when the
    /// test ends, so what a test records lands nowhere else and stays nowhere.
    func freshDefaults() throws -> UserDefaults {
        let name = "bud.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    /// A layout on a fresh suite: the table's defaults and nothing recorded over them.
    func freshLayout(desktop: Bool = KeyLayout.isDesktop) throws -> KeyLayout {
        KeyLayout(defaults: try freshDefaults(), desktop: desktop)
    }
}
