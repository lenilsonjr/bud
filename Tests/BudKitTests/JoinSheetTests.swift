import XCTest
@testable import BudKit

final class JoinSheetTests: XCTestCase {
    func testTheThreeFailuresReadAsTheFrame() {
        XCTAssertEqual(JoinText.failureTitle(.usedOrExpired), "That ticket was already used")
        XCTAssertEqual(JoinText.failureBody(.usedOrExpired), "Each ticket works once, for ten minutes. Ask the other device for a fresh one.")
        XCTAssertEqual(JoinText.failureTitle(.notATicket), "That isn’t a Bud ticket")
        XCTAssertEqual(JoinText.failureBody(.notATicket), "It should start with bud1. Check for a missing piece.")
        XCTAssertEqual(JoinText.failureTitle(.unreachable), "Couldn’t reach the other device")
        XCTAssertEqual(JoinText.failureBody(.unreachable), "Keep it open, on the same network or online, and try again.")
    }

    func testTheEntryStatusFollowsTheText() {
        XCTAssertEqual(EntryStatus(text: "bud1 29326 ml64l g2tjf 8cz2k a7edc mpb3u 2m7", failed: false), .typing(count: "37 of 134"))
        let full = "bud1" + String(repeating: "x", count: 130)
        XCTAssertEqual(EntryStatus(text: PeerText.grouped(full), failed: false), .looksLikeTicket)
        XCTAssertTrue(EntryStatus(text: full, failed: false).canJoin)
        XCTAssertEqual(EntryStatus(text: full, failed: true), .checked)
        XCTAssertFalse(EntryStatus(text: full, failed: true).canJoin)
        XCTAssertEqual(EntryStatus.looksLikeTicket.label, "Looks like a ticket")
        XCTAssertEqual(EntryStatus.checked.label, "Checked")
    }

    func testTheJoinedLinesNameTheSourceAndTheProgress() {
        let source = Device(id: "a91cp4x8d2n6w0j3h5v9b1m7r2ks7t0e", reach: .local)
        XCTAssertEqual(
            JoinText.joinedBody(from: source),
            "Getting buds from a91c…7t0e on the local network. You can start while it finishes.")
        XCTAssertEqual(JoinText.reachPhrase(.relay), "through a relay")
        XCTAssertEqual(JoinText.reachPhrase(.direct), "directly")
        XCTAssertEqual(JoinText.progress(received: 214, total: 1380), "214 of 1,380 buds")
        XCTAssertEqual(JoinText.progress(received: 214, total: nil), "214 buds so far")
        XCTAssertEqual(JoinText.progress(received: 1, total: nil), "1 bud so far")
        XCTAssertEqual(JoinText.grouped(1_234_567), "1,234,567")
        XCTAssertEqual(JoinText.grouped(999), "999")
        XCTAssertEqual(JoinText.fraction(received: 345, total: 1380), 0.25)
        XCTAssertNil(JoinText.fraction(received: 3, total: nil), "No total means an indeterminate bar")
        XCTAssertEqual(JoinText.fraction(received: 9, total: 4), 1, "It never goes past the end")
    }
}
