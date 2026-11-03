import XCTest
@testable import BudKit

final class PhonePaletteTests: XCTestCase {
    func testThePaletteOpensOnceWhenTheNavigatorIsPulledPastTheThreshold() {
        var pull = PhonePalette.Pull()
        XCTAssertFalse(pull.offset(12), "the first position is where the navigator rests")
        XCTAssertFalse(pull.offset(40))
        XCTAssertFalse(pull.offset(91), "79 points is short of the threshold")
        XCTAssertTrue(pull.offset(92), "80 points opens it")
        XCTAssertFalse(pull.offset(120), "pulling further does not open it again")
        XCTAssertFalse(pull.offset(50), "nor does easing back a little")
    }

    func testThePullArmsAgainOnlyAfterTheNavigatorRests() {
        var pull = PhonePalette.Pull()
        _ = pull.offset(0)
        XCTAssertTrue(pull.offset(80))
        XCTAssertFalse(pull.offset(80))
        XCTAssertFalse(pull.offset(0), "resting arms it")
        XCTAssertTrue(pull.offset(100))
    }

    func testScrollingUpThroughTheTreeNeverOpensIt() {
        var pull = PhonePalette.Pull()
        _ = pull.offset(0)
        for y in stride(from: -20.0, through: -900, by: -40) {
            XCTAssertFalse(pull.offset(y))
        }
    }

    func testTheLongPressOffersTheOtherWay() {
        XCTAssertEqual(PhonePalette.otherWay(inFiles: true), "Center on canvas")
        XCTAssertEqual(PhonePalette.otherWay(inFiles: false), "Open in Files")
    }
}
