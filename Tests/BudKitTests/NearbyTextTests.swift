import XCTest
@testable import BudKit

final class NearbyTextTests: XCTestCase {
    func testEveryFailureHasATitleAndABody() {
        let errors: [RequestError] = [.notARequest, .expired, .unreachable, .refused]
        let titles = Set(errors.map(NearbyText.failureTitle))
        XCTAssertEqual(titles.count, errors.count, "each failure reads differently")
        for error in errors {
            XCTAssertFalse(NearbyText.failureBody(error).isEmpty)
        }
        XCTAssertEqual(NearbyText.failureTitle(.refused), "The other device said no")
    }

    func testTheAddedLineNamesTheDevice() {
        let named = Device(id: "a", name: "Den", kind: .tv)
        XCTAssertEqual(NearbyText.addedBody(named), "Den is in the vault and fetching it now.")
        let unnamed = Device(id: "b", kind: .tv)
        XCTAssertEqual(NearbyText.addedBody(unnamed), "The Apple TV is in the vault and fetching it now.")
    }

    func testTheAppleTVPointsAtThisSheet() {
        XCTAssertTrue(TVDevicesText.requestNote.contains(NearbyText.title))
    }
}
