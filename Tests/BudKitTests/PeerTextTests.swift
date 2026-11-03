import XCTest
@testable import BudKit

final class PeerTextTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func ticketText(length: Int = PeerText.ticketLength) -> String {
        "bud1" + String(repeating: "a", count: length - 4)
    }

    func testTicketTextIsGroupedInFives() {
        XCTAssertEqual(PeerText.grouped("bud129326ml64lzz"), "bud12 9326m l64lz z")
    }

    func testGroupingIgnoresSpacesAlreadyThere() {
        XCTAssertEqual(PeerText.grouped("bud12 9326m l64lz z"), "bud12 9326m l64lz z")
    }

    func testTypedCountCountsTheCharactersWithoutSpaces() {
        XCTAssertEqual(PeerText.typedCount("bud12 9326m l64lz z"), "16 of 134")
        XCTAssertEqual(PeerText.typedCount(""), "0 of 134")
    }

    func testLooksLikeATicket() {
        XCTAssertTrue(PeerText.looksLikeTicket(ticketText()))
        XCTAssertTrue(PeerText.looksLikeTicket("  " + PeerText.grouped(ticketText()).uppercased() + "\n"))
    }

    func testLooksLikeATicketToleratesALittleLengthDrift() {
        XCTAssertTrue(PeerText.looksLikeTicket(ticketText(length: PeerText.ticketLength - PeerText.ticketTolerance)))
        XCTAssertTrue(PeerText.looksLikeTicket(ticketText(length: PeerText.ticketLength + PeerText.ticketTolerance)))
        XCTAssertFalse(PeerText.looksLikeTicket(ticketText(length: PeerText.ticketLength - PeerText.ticketTolerance - 1)))
        XCTAssertFalse(PeerText.looksLikeTicket(ticketText(length: PeerText.ticketLength + PeerText.ticketTolerance + 1)))
    }

    func testLooksLikeATicketNeedsTheRightStart() {
        XCTAssertFalse(PeerText.looksLikeTicket("xyz2" + String(repeating: "a", count: 130)))
        XCTAssertFalse(PeerText.looksLikeTicket(""))
    }

    func testSeenLabels() {
        func label(_ seconds: TimeInterval) -> String { PeerText.seen(now.addingTimeInterval(-seconds), now: now) }
        XCTAssertEqual(label(0), "seen just now")
        XCTAssertEqual(label(45), "seen just now")
        XCTAssertEqual(label(60), "seen 1 minute ago")
        XCTAssertEqual(label(4 * 60 + 10), "seen 4 minutes ago")
        XCTAssertEqual(label(2 * 3600 + 5), "seen 2 hours ago")
        XCTAssertEqual(label(3600), "seen 1 hour ago")
        XCTAssertEqual(label(3 * 86400), "seen 3 days ago")
        XCTAssertEqual(label(86400), "seen 1 day ago")
    }

    func testSeenIsJustNowForAFutureDate() {
        XCTAssertEqual(PeerText.seen(now.addingTimeInterval(30), now: now), "seen just now")
    }

    func testNeverSeen() {
        XCTAssertEqual(PeerText.seen(nil, now: now), "not seen yet")
    }

    func testCountdown() {
        let expires = now.addingTimeInterval(600)
        XCTAssertEqual(PeerText.countdown(until: expires, now: now), "10:00")
        XCTAssertEqual(PeerText.countdown(until: expires, now: now.addingTimeInterval(2)), "9:58")
        XCTAssertEqual(PeerText.countdown(until: expires, now: now.addingTimeInterval(595.5)), "0:05")
        XCTAssertEqual(PeerText.countdown(until: expires, now: now.addingTimeInterval(600)), "0:00")
        XCTAssertEqual(PeerText.countdown(until: expires, now: now.addingTimeInterval(900)), "0:00")
    }

    func testShortID() {
        XCTAssertEqual(PeerText.shortID("k7f3abcdefghijklmnopq2m9"), "k7f3…q2m9")
        XCTAssertEqual(PeerText.shortID("short"), "short")
    }

    func testAcceptErrorsAreMappedFromTheCoreMessages() {
        XCTAssertEqual(AcceptError(message: "peer: not a pairing ticket"), .notATicket)
        XCTAssertEqual(AcceptError(message: "peer: refused"), .usedOrExpired)
        XCTAssertEqual(AcceptError(message: "peer: could not reach the vault"), .unreachable)
        XCTAssertNil(AcceptError(message: "something else"))
    }

    func testTicketExpiresTenMinutesAfterItWasMade() {
        let ticket = Ticket(text: "bud1", qr: [[true]], madeAt: now)
        XCTAssertEqual(ticket.expiresAt, now.addingTimeInterval(600))
    }


    func testWhatLooksLikeAJoinRequest() {
        let code = PeerText.requestPrefix + String(repeating: "k7f3c8z1q5", count: 17)
        XCTAssertTrue(PeerText.looksLikeRequest(code))
        XCTAssertTrue(PeerText.looksLikeRequest(code.uppercased()))
        XCTAssertTrue(PeerText.looksLikeRequest(PeerText.grouped(code)), "spaces do not matter")
        XCTAssertFalse(PeerText.looksLikeRequest("bud1" + String(repeating: "k7f3c8z1q5", count: 13)), "a ticket")
        XCTAssertFalse(PeerText.looksLikeRequest(PeerText.requestPrefix + "short"))
        XCTAssertFalse(PeerText.looksLikeRequest(code + "!"))
    }
}
