import XCTest
@testable import BudKit

final class TitleFadeTests: XCTestCase {
    func testALabelThatFitsIsDrawnWhole() {
        XCTAssertFalse(TitleFade.needsFade(textWidth: 120, availableWidth: 140))
    }

    func testALabelThatFillsTheRoomExactlyIsDrawnWhole() {
        XCTAssertFalse(TitleFade.needsFade(textWidth: 140, availableWidth: 140))
    }

    func testALabelThatOverlapsTheCountFades() {
        XCTAssertTrue(TitleFade.needsFade(textWidth: 141, availableWidth: 140))
    }

    func testBeforeAnythingIsMeasuredNothingFades() {
        XCTAssertFalse(TitleFade.needsFade(textWidth: 0, availableWidth: 0))
    }

    func testRoundingNoiseDoesNotFadeALabelThatFits() {
        XCTAssertFalse(TitleFade.needsFade(textWidth: 140.2, availableWidth: 140))
    }
}
