import XCTest
@testable import BudKit

final class TicketSheetTests: XCTestCase {
    private let made = Date(timeIntervalSince1970: 1_800_000_000)

    private func ticket() -> Ticket {
        Ticket(text: "bud1" + String(repeating: "k7f3q", count: 26), qr: [[true]], madeAt: made)
    }

    func testTheLayoutPutsA184PointCodeInsideA216PointTile() {
        let layout = QRLayout(modules: 25)
        XCTAssertEqual(layout.code, 184, accuracy: 0.001)
        XCTAssertEqual(layout.inset, 16, accuracy: 0.001)
        XCTAssertEqual(layout.module, 7.36, accuracy: 0.001)
        let last = layout.square(row: 24, column: 24)
        XCTAssertEqual(last.x, 16 + 24 * 7.36, accuracy: 0.001)
        XCTAssertEqual(last.y, last.x, accuracy: 0.001)
        XCTAssertEqual(last.x + last.side, 200, accuracy: 0.001)
    }

    func testTheTVTileKeepsTheSameShare() {
        let tv = QRLayout(size: 280, modules: 29)
        XCTAssertEqual(tv.code, 238.56, accuracy: 0.1)
        XCTAssertEqual(tv.inset, 20.72, accuracy: 0.1)
        XCTAssertEqual(QRLayout(modules: 0).modules, 1)
    }

    func testTheSheetIsMakingBeforeATicketExists() {
        XCTAssertEqual(TicketSheetState(ticket: nil, now: made, redeemedBy: nil), .making)
        XCTAssertEqual(TicketSheetState.making.status, "")
    }

    func testAFreshTicketCountsDown() {
        let state = TicketSheetState(ticket: ticket(), now: made.addingTimeInterval(2), redeemedBy: nil)
        XCTAssertEqual(state, .fresh(countdown: "9:58"))
        XCTAssertEqual(state.status, "Works once · expires in 9:58")
        XCTAssertFalse(state.isExpired)
    }

    func testTenMinutesLaterTheTicketIsExpired() {
        let state = TicketSheetState(ticket: ticket(), now: made.addingTimeInterval(600), redeemedBy: nil)
        XCTAssertEqual(state, .expired)
        XCTAssertTrue(state.isExpired)
        XCTAssertEqual(state.status, "Expired · works once, for ten minutes")
    }

    func testARedeemedTicketTurnsTheSheetIntoJoined() {
        let state = TicketSheetState(ticket: ticket(), now: made.addingTimeInterval(900), redeemedBy: "k7f3abcdefghijklmnopqrstuvwxq2m9")
        XCTAssertEqual(state, .joined(shortID: "k7f3…q2m9"))
        XCTAssertFalse(state.isExpired)
    }
}
