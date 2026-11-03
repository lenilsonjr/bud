import XCTest
@testable import BudKit

final class TVDevicesTextTests: XCTestCase {
    func testTheStatusLineReadsTheSyncState() {
        XCTAssertEqual(TVDevicesText.status(SyncState(idle: true, connectedPeers: 2, pendingChanges: 0)), "2 connected · everything synced")
        XCTAssertEqual(TVDevicesText.status(SyncState(idle: true, connectedPeers: 1, pendingChanges: 3)), "1 connected · 3 changes waiting")
        XCTAssertEqual(TVDevicesText.status(SyncState(idle: true, connectedPeers: 0, pendingChanges: 1)), "0 connected · 1 change waiting")
        XCTAssertEqual(TVDevicesText.status(SyncState(idle: false, connectedPeers: 2, pendingChanges: 0)), "2 connected · syncing")
        XCTAssertEqual(TVDevicesText.status(nil), "Not connected yet")
    }

    func testTheExpiryCountsDownToANewCode() async throws {
        let made = Date(timeIntervalSince1970: 1_800_000_000)
        let peers = MemoryPeers(now: { made })
        let ticket = try await peers.ticket(withAddresses: false)
        XCTAssertEqual(TVDevicesText.expiry(ticket, now: made.addingTimeInterval(2)), "Works once · new code in 9:58")
        XCTAssertEqual(TVDevicesText.expiry(nil, now: made), "Making a ticket…")
    }

    func testTheFetchScreenNamesTheSourceAndKnowsWhenItIsDone() {
        let source = Device(id: "a91cp4x8d2n6w0j3h5v9b1m7r2ks7t0e", reach: .local)
        XCTAssertEqual(TVDevicesText.fetchBody(from: source), "Joined. Fetching the whole vault from a91c…7t0e on the local network.")
        XCTAssertFalse(TVDevicesText.fetchIsDone(received: 214, total: 1380))
        XCTAssertTrue(TVDevicesText.fetchIsDone(received: 1380, total: 1380))
        XCTAssertFalse(TVDevicesText.fetchIsDone(received: 900, total: nil), "No total means the first sync's end decides")
    }


    func testTheRequestColumnLines() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(TVDevicesText.requestExpiry(nil, now: now), "Making a code…")
        let request = JoinRequest(code: "budr1", qr: [], words: ["amber", "cedar", "harbor", "lantern"], madeAt: now)
        XCTAssertEqual(TVDevicesText.requestExpiry(request, now: now.addingTimeInterval(2)), "Works once · new code in 9:58")
        XCTAssertEqual(TVDevicesText.wordsLine(request.words), "amber · cedar · harbor · lantern")
        XCTAssertEqual(TVDevicesText.typeInstead, "Type a ticket instead")
        XCTAssertTrue(TVDevicesText.requestNote.contains("words match"))
    }
}
