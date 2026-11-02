import XCTest
@testable import BudKit

final class SidebarVisibilityTests: XCTestCase {
    private let landscape = CGSize(width: 1024, height: 768)
    private let portrait = CGSize(width: 768, height: 1024)

    func testTheSidebarShowsInLandscapeAndCollapsesInPortrait() {
        let bar = SidebarVisibility()
        XCTAssertTrue(bar.isShown(in: landscape))
        XCTAssertFalse(bar.isShown(in: portrait))
    }

    func testANarrowLandscapeWindowStaysCollapsed() {
        XCTAssertFalse(SidebarVisibility().isShown(in: CGSize(width: 600, height: 400)))
    }

    func testTheToggleFlipsWhatIsShown() {
        var bar = SidebarVisibility()
        bar.toggle(in: landscape)
        XCTAssertFalse(bar.isShown(in: landscape))
        bar.toggle(in: landscape)
        XCTAssertTrue(bar.isShown(in: landscape))

        var closed = SidebarVisibility()
        closed.toggle(in: portrait)
        XCTAssertTrue(closed.isShown(in: portrait))
    }

    func testTurningTheDeviceHandsTheChoiceBackToTheLayout() {
        var bar = SidebarVisibility()
        bar.toggle(in: landscape)
        bar.resized(to: landscape)
        XCTAssertFalse(bar.isShown(in: landscape))
        bar.resized(to: portrait)
        XCTAssertFalse(bar.isShown(in: portrait))
        bar.resized(to: landscape)
        XCTAssertTrue(bar.isShown(in: landscape))
    }

    func testResizingWithinOneOrientationKeepsTheChoice() {
        var bar = SidebarVisibility()
        bar.resized(to: portrait)
        bar.toggle(in: portrait)
        bar.resized(to: CGSize(width: 700, height: 1000))
        XCTAssertTrue(bar.isShown(in: CGSize(width: 700, height: 1000)))
    }
}
