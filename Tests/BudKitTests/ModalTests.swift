import XCTest
@testable import BudKit

final class ModalTests: XCTestCase {
    func testAddingUnderTheHubPlantsOnTheCanvas() {
        XCTAssertEqual(Modal.adding(under: rootID), .add(parent: rootID))
        let other = UUID()
        XCTAssertEqual(Modal.adding(under: other), .add(parent: other))
    }

    func testEachModalHasItsOwnIdentity() {
        let a = UUID()
        let b = UUID()
        XCTAssertNotEqual(Modal.add(parent: a).id, Modal.add(parent: b).id)
        XCTAssertNotEqual(Modal.add(parent: a).id, Modal.capture.id)
        XCTAssertEqual(Modal.add(parent: a).id, Modal.add(parent: a).id)
    }

    func testCardWidthIs480OrTheWindowMinus32WhenNarrower() {
        XCTAssertEqual(ModalMetrics.cardWidth(window: 1400), 480)
        XCTAssertEqual(ModalMetrics.cardWidth(window: 512), 480)
        XCTAssertEqual(ModalMetrics.cardWidth(window: 390), 358)
    }

    func testCardMetricsFollowTheKit() {
        XCTAssertEqual(ModalMetrics.padding, 24)
        XCTAssertEqual(ModalMetrics.appearScale, 0.96)
        XCTAssertEqual(ModalMetrics.appearDuration, 0.18)
        XCTAssertEqual(Radius.xl, 22)
    }

    func testButtonMetricsFollowTheKit() {
        XCTAssertEqual(ButtonMetrics.cornerRadius, 8)
        XCTAssertEqual(ButtonMetrics.verticalPadding, 7)
        XCTAssertEqual(ButtonMetrics.horizontalPadding, 12)
        XCTAssertEqual(ButtonMetrics.iconSize, 14)
        XCTAssertEqual(ButtonMetrics.labelSize, 13)
        XCTAssertEqual(ButtonMetrics.pressedOpacity, 0.85)
    }

    func testButtonColoursMatchTheKit() {
        XCTAssertEqual(Palette.leafFill, Tone("#3F7F48", "#8CCC8C"))
        XCTAssertEqual(Palette.onLeaf, Tone("#FFFFFF", "#0E1C13"))
        XCTAssertEqual(Palette.scrim, Tone("#1B2E2138", "#040A06A6"))
    }
}
