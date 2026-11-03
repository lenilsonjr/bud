import XCTest
@testable import BudKit

/// A clock a test moves by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { current = start }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }
}

final class MemoryPeersTests: XCTestCase {
    private func make(missing: Set<String> = []) -> (MemoryPeers, TestClock) {
        let clock = TestClock()
        return (MemoryPeers(missing: missing, now: { clock.now }), clock)
    }

    func testItStartsWithTheFixtureDevices() async throws {
        let (peers, _) = make()
        let devices = try await peers.devices()
        XCTAssertEqual(devices.map { PeerText.shortID($0.id) }, ["a91c…7t0e", "k7f3…q2m9", "m2pd…h81k", "t6vb…2kxe", "c55w…0pdl"])
        XCTAssertEqual(devices.filter(\.isThisDevice).count, 1)
        XCTAssertEqual(devices.first?.isThisDevice, true)
    }

    func testATicketCarriesTextQrAndALifetime() async throws {
        let (peers, clock) = make()
        let ticket = try await peers.ticket(withAddresses: false)
        XCTAssertTrue(PeerText.looksLikeTicket(ticket.text))
        XCTAssertFalse(ticket.qr.isEmpty)
        XCTAssertEqual(ticket.madeAt, clock.now)
        XCTAssertEqual(ticket.expiresAt, clock.now.addingTimeInterval(600))
    }

    func testEveryTicketIsNew() async throws {
        let (peers, _) = make()
        let first = try await peers.ticket(withAddresses: false)
        let second = try await peers.ticket(withAddresses: true)
        XCTAssertNotEqual(first.text, second.text)
    }

    func testAcceptAddsADeviceAndFiresTheRedeemedEvent() async throws {
        let (peers, _) = make()
        var events = try await peers.events().makeAsyncIterator()
        let ticket = try await peers.ticket(withAddresses: false)
        let device = try await peers.accept(PeerText.grouped(ticket.text))
        let all = try await peers.devices()
        XCTAssertEqual(all.count, 6)
        XCTAssertTrue(all.contains(device))
        XCTAssertFalse(device.isThisDevice)
        let redeemed = await events.next()
        XCTAssertEqual(redeemed, .ticketRedeemed(by: device.id))
        let joined = await events.next()
        XCTAssertEqual(joined, .deviceJoined(device))
    }

    func testATicketWorksOnce() async throws {
        let (peers, _) = make()
        let ticket = try await peers.ticket(withAddresses: false)
        _ = try await peers.accept(ticket.text)
        await assertAccept(peers, ticket.text, throws: .usedOrExpired)
    }

    func testATicketExpires() async throws {
        let (peers, clock) = make()
        let ticket = try await peers.ticket(withAddresses: false)
        clock.advance(601)
        await assertAccept(peers, ticket.text, throws: .usedOrExpired)
        let all = try await peers.devices()
        XCTAssertEqual(all.count, 5)
    }

    func testTextThatIsNotATicketIsRefused() async {
        let (peers, _) = make()
        await assertAccept(peers, "hello", throws: .notATicket)
        await assertAccept(peers, "xyz2" + String(repeating: "a", count: 130), throws: .notATicket)
    }

    func testATicketFromAnotherVaultCannotBeReached() async {
        let (peers, _) = make()
        await assertAccept(peers, "bud1" + String(repeating: "q", count: 130), throws: .unreachable)
    }

    func testAnUnreachableVaultFailsEveryAccept() async throws {
        let (peers, _) = make()
        let ticket = try await peers.ticket(withAddresses: false)
        await peers.setReachable(false)
        await assertAccept(peers, ticket.text, throws: .unreachable)
        await peers.setReachable(true)
        _ = try await peers.accept(ticket.text)
    }

    func testRemoveForgetsTheDevice() async throws {
        let (peers, _) = make()
        let target = try await peers.devices()[1]
        try await peers.remove(target.id)
        let all = try await peers.devices()
        XCTAssertFalse(all.contains { $0.id == target.id })
        do {
            try await peers.remove(target.id)
            XCTFail("a second remove should fail")
        } catch {
            XCTAssertEqual(error as? PeersError, .noSuchDevice(target.id))
        }
    }

    func testRotationStreamsOneStepPerDeviceAndEndsInAResult() async throws {
        let (peers, _) = make()
        var steps: [RotationStep] = []
        for await step in try await peers.rotateKey() { steps.append(step) }
        let others = try await peers.devices().filter { !$0.isThisDevice }
        XCTAssertEqual(steps.count, others.count + 1)
        XCTAssertEqual(steps.last, .done(RotationResult(reached: others.count, missed: [])))
        XCTAssertEqual(steps.dropLast().map(\.deviceID), others.map(\.id))
    }

    func testRotationReportsTheDeviceThatMisses() async throws {
        let (peers, _) = make()
        let missing = try await peers.devices()[2].id
        await peers.setMissing([missing])
        var steps: [RotationStep] = []
        for await step in try await peers.rotateKey() { steps.append(step) }
        XCTAssertEqual(steps.last, .done(RotationResult(reached: 3, missed: [missing])))
        XCTAssertTrue(steps.contains(.device(id: missing, reached: false)))
        let flagged = try await peers.devices().first { $0.id == missing }
        XCTAssertEqual(flagged?.missed, true)
    }

    func testAllowClearsAMissedDevice() async throws {
        let (peers, _) = make()
        let id = try await peers.devices()[1].id
        await peers.setMissing([id])
        for await _ in try await peers.rotateKey() {}
        try await peers.allow(id)
        let device = try await peers.devices().first { $0.id == id }
        XCTAssertEqual(device?.missed, false)
    }

    func testSyncNowReturnsTheSummaryAndFiresAnEvent() async throws {
        let (peers, _) = make()
        let summary = SyncSummary(created: 2, updated: 1, written: 3, moved: 0, ops: 6)
        await peers.setNextSummary(summary)
        var events = try await peers.events().makeAsyncIterator()
        let result = try await peers.syncNow()
        XCTAssertEqual(result, summary)
        let event = await events.next()
        XCTAssertEqual(event, .syncFinished(summary))
    }

    func testStateCountsTheConnectedPeers() async throws {
        let (peers, _) = make()
        let state = try await peers.state()
        XCTAssertEqual(state, SyncState(idle: true, connectedPeers: 4, pendingChanges: 0))
        await peers.setPendingChanges(3)
        let busy = try await peers.state()
        XCTAssertEqual(busy.pendingChanges, 3)
    }

    func testRelayRoundTrips() async throws {
        let (peers, _) = make()
        let initial = try await peers.relay()
        XCTAssertEqual(initial, .default)
        let url = try XCTUnwrap(URL(string: "https://relay.example.org"))
        try await peers.setRelay(.custom(url))
        let custom = try await peers.relay()
        XCTAssertEqual(custom, .custom(url))
        try await peers.setRelay(.off)
        let off = try await peers.relay()
        XCTAssertEqual(off, .off)
    }

    func testATestDrivesFetchProgress() async throws {
        let (peers, _) = make()
        var events = try await peers.events().makeAsyncIterator()
        await peers.emitFetchProgress(received: 37, total: 134)
        await peers.emitFetchProgress(received: 40, total: nil)
        let first = await events.next()
        XCTAssertEqual(first, .fetchProgress(received: 37, total: 134))
        let second = await events.next()
        XCTAssertEqual(second, .fetchProgress(received: 40, total: nil))
    }

    private func assertAccept(_ peers: MemoryPeers, _ text: String, throws expected: AcceptError, line: UInt = #line) async {
        do {
            _ = try await peers.accept(text)
            XCTFail("accept should have thrown", line: line)
        } catch {
            XCTAssertEqual(error as? AcceptError, expected, line: line)
        }
    }


    func testAJoinRequestCarriesACodeAQrFourWordsAndALifetime() async throws {
        let (peers, clock) = make()
        let request = try await peers.joinRequest()
        XCTAssertTrue(PeerText.looksLikeRequest(request.code))
        XCTAssertEqual(request.qr.count, 29)
        XCTAssertEqual(request.words.count, 4)
        XCTAssertEqual(request.madeAt, clock.now)
        XCTAssertEqual(request.expiresAt, clock.now.addingTimeInterval(JoinRequest.lifetime))
        let next = try await peers.joinRequest()
        XCTAssertNotEqual(next.code, request.code)
    }

    func testReadingARequestGivesItsWordsAndConfirmingAddsTheDeviceAndTellsIt() async throws {
        let (peers, _) = make()
        let events = try await peers.events()
        let request = try await peers.joinRequest()
        let words = try await peers.readRequest(request.code.uppercased())
        XCTAssertEqual(words, request.words, "the same four words on both sides")
        let before = try await peers.devices().count
        let device = try await peers.confirmRequest(request.code)
        XCTAssertEqual(device.kind, .tv)
        let after = try await peers.devices()
        XCTAssertEqual(after.count, before + 1)
        XCTAssertEqual(after.last, device)
        var iterator = events.makeAsyncIterator()
        let event = await iterator.next()
        XCTAssertEqual(event, .deviceJoined(device))
    }

    func testARequestWorksOnceAndExpiresAndAStrangeCodeIsRefused() async throws {
        let (peers, clock) = make()
        let request = try await peers.joinRequest()
        _ = try await peers.confirmRequest(request.code)
        await XCTAssertThrowsRequest(.refused) { _ = try await peers.confirmRequest(request.code) }
        let later = try await peers.joinRequest()
        clock.advance(JoinRequest.lifetime + 1)
        await XCTAssertThrowsRequest(.expired) { _ = try await peers.readRequest(later.code) }
        await XCTAssertThrowsRequest(.expired) { _ = try await peers.confirmRequest(later.code) }
        await XCTAssertThrowsRequest(.notARequest) { _ = try await peers.readRequest("bud1 not a request") }
        let unknown = PeerText.requestPrefix + String(repeating: "q", count: 160)
        let elsewhere = try await peers.readRequest(unknown)
        XCTAssertEqual(elsewhere.count, 4, "a code from elsewhere reads")
        await XCTAssertThrowsRequest(.unreachable) { _ = try await peers.confirmRequest(unknown) }
        await peers.setRequestFailure(.refused)
        await XCTAssertThrowsRequest(.refused) { _ = try await peers.readRequest(unknown) }
    }

    private func XCTAssertThrowsRequest(
        _ expected: RequestError, line: UInt = #line, _ run: () async throws -> Void
    ) async {
        do {
            try await run()
            XCTFail("nothing was thrown", line: line)
        } catch let error as RequestError {
            XCTAssertEqual(error, expected, line: line)
        } catch {
            XCTFail("another error: \(error)", line: line)
        }
    }
}
