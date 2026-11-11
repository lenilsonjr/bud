import XCTest
@testable import BudKit

final class TVForegroundTests: XCTestCase {
    func testABackFromTheBackgroundSyncsOnce() {
        var foreground = TVForeground()
        XCTAssertFalse(foreground.moved(to: .inactive))
        XCTAssertFalse(foreground.moved(to: .background))
        XCTAssertFalse(foreground.moved(to: .inactive))
        XCTAssertTrue(foreground.moved(to: .active))
        // An overlay right after asks for nothing more.
        XCTAssertFalse(foreground.moved(to: .inactive))
        XCTAssertFalse(foreground.moved(to: .active))
    }

    func testASystemOverlayAsksForNoSync() {
        var foreground = TVForeground()
        for _ in 0..<3 {
            XCTAssertFalse(foreground.moved(to: .inactive))
            XCTAssertFalse(foreground.moved(to: .active))
        }
    }

    func testEveryTripThroughTheBackgroundSyncs() {
        var foreground = TVForeground()
        for _ in 0..<2 {
            _ = foreground.moved(to: .inactive)
            _ = foreground.moved(to: .background)
            XCTAssertTrue(foreground.moved(to: .active))
        }
    }

    func testTheLaunchItselfAsksForNoSync() {
        var foreground = TVForeground()
        XCTAssertFalse(foreground.moved(to: .active))
    }
}
