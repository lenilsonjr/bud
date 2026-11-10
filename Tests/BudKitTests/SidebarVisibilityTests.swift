import XCTest
@testable import BudKit

final class SidebarVisibilityTests: XCTestCase {
    private let landscape = CGSize(width: 1024, height: 768)
    private let portrait = CGSize(width: 768, height: 1024)

    func testTheSidebarsShowInLandscapeAndCollapseInPortrait() {
        let bar = SidebarVisibility()
        XCTAssertTrue(bar.isShown(.left, in: landscape))
        XCTAssertTrue(bar.isShown(.right, in: landscape))
        XCTAssertFalse(bar.isShown(.left, in: portrait))
        XCTAssertFalse(bar.isShown(.right, in: portrait))
    }

    func testANarrowLandscapeWindowStaysCollapsed() {
        XCTAssertFalse(SidebarVisibility().isShown(.left, in: CGSize(width: 600, height: 400)))
    }

    func testAWindowWithRoomShowsBothUntilAToggleHidesOne() {
        var bar = SidebarVisibility(followsWindow: false)
        XCTAssertTrue(bar.isShown(.left, in: portrait))
        XCTAssertTrue(bar.isShown(.right, in: CGSize(width: 600, height: 400)))
        bar.toggle(.right, in: portrait)
        XCTAssertFalse(bar.isShown(.right, in: portrait))
        XCTAssertTrue(bar.isShown(.left, in: portrait))
    }

    func testTheToggleFlipsOneSideAndLeavesTheOther() {
        var bar = SidebarVisibility()
        bar.toggle(.left, in: landscape)
        XCTAssertFalse(bar.isShown(.left, in: landscape))
        XCTAssertTrue(bar.isShown(.right, in: landscape))
        bar.toggle(.left, in: landscape)
        XCTAssertTrue(bar.isShown(.left, in: landscape))

        var closed = SidebarVisibility()
        closed.toggle(.right, in: portrait)
        XCTAssertTrue(closed.isShown(.right, in: portrait))
        XCTAssertFalse(closed.isShown(.left, in: portrait))
    }

    func testTurningTheDeviceHandsTheChoiceBackToTheLayout() {
        var bar = SidebarVisibility()
        bar.toggle(.left, in: landscape)
        bar.toggle(.right, in: landscape)
        bar.resized(to: landscape)
        XCTAssertFalse(bar.isShown(.left, in: landscape))
        bar.resized(to: portrait)
        XCTAssertFalse(bar.isShown(.left, in: portrait))
        XCTAssertFalse(bar.isShown(.right, in: portrait))
        bar.resized(to: landscape)
        XCTAssertTrue(bar.isShown(.left, in: landscape))
        XCTAssertTrue(bar.isShown(.right, in: landscape))
    }

    func testResizingWithinOneOrientationKeepsTheChoice() {
        var bar = SidebarVisibility()
        bar.resized(to: portrait)
        bar.toggle(.left, in: portrait)
        bar.resized(to: CGSize(width: 700, height: 1000))
        XCTAssertTrue(bar.isShown(.left, in: CGSize(width: 700, height: 1000)))
    }
}
