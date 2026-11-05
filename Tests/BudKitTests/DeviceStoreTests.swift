import XCTest
@testable import BudKit

@MainActor
final class DeviceStoreTests: XCTestCase {
    private func make(lifetime: TimeInterval = 600, missing: Set<String> = []) async -> (DeviceStore, MemoryPeers, TestClock) {
        let clock = TestClock()
        let peers = MemoryPeers(lifetime: lifetime, missing: missing, now: { clock.now })
        let store = DeviceStore(peers: peers, now: { clock.now })
        await store.start()
        return (store, peers, clock)
    }

    private func eventually(_ condition: @MainActor () -> Bool, line: UInt = #line) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("the condition never held", line: line)
    }

    func testItListsTheDevicesAndTheSyncState() async {
        let (store, _, _) = await make()
        XCTAssertEqual(store.devices.count, 5)
        XCTAssertEqual(store.syncState, SyncState(idle: true, connectedPeers: 4, pendingChanges: 0))
        XCTAssertNil(store.lastSummary)
        XCTAssertEqual(store.shortID("k7f3abcdefghijklmnopq2m9"), "k7f3…q2m9")
    }

    func testSyncNowKeepsTheSummary() async {
        let (store, peers, _) = await make()
        let summary = SyncSummary(created: 1, updated: 2, written: 0, moved: 0, ops: 3)
        await peers.setNextSummary(summary)
        await store.syncNow()
        XCTAssertEqual(store.lastSummary, summary)
    }

    func testTheTicketSheetGetsATicketAndRefreshesItOnExpiry() async throws {
        let (store, _, clock) = await make()
        await store.openTicket()
        let first = try XCTUnwrap(store.currentTicket)
        await store.refreshTicketIfExpired()
        XCTAssertEqual(store.currentTicket, first)
        clock.advance(601)
        await store.refreshTicketIfExpired()
        let second = try XCTUnwrap(store.currentTicket)
        XCTAssertNotEqual(second.text, first.text)
        store.closeTicket()
        XCTAssertNil(store.currentTicket)
    }

    func testAClosedSheetDoesNotRefresh() async {
        let (store, _, clock) = await make()
        await store.openTicket()
        store.closeTicket()
        clock.advance(601)
        await store.refreshTicketIfExpired()
        XCTAssertNil(store.currentTicket)
    }

    func testTheOpenTicketRefreshesByItself() async throws {
        let store = DeviceStore(peers: MemoryPeers(lifetime: 0.05))
        await store.openTicket()
        let first = try XCTUnwrap(store.currentTicket)
        await eventually { store.currentTicket != nil && store.currentTicket?.text != first.text }
        store.closeTicket()
    }

    func testJoiningWithATicketSucceeds() async throws {
        let (store, peers, _) = await make()
        let ticket = try await peers.ticket(withAddresses: false)
        XCTAssertEqual(store.joinPhase, .idle)
        await store.join(text: PeerText.grouped(ticket.text))
        guard case let .joined(device, received, total) = store.joinPhase else {
            return XCTFail("expected joined, got \(store.joinPhase)")
        }
        XCTAssertEqual(received, 0)
        XCTAssertNil(total)
        XCTAssertTrue(store.devices.contains(device))
        XCTAssertEqual(store.devices.count, 6)
    }

    func testFetchProgressUpdatesTheJoinedPhase() async throws {
        let (store, peers, _) = await make()
        let ticket = try await peers.ticket(withAddresses: false)
        await store.join(text: ticket.text)
        await peers.emitFetchProgress(received: 37, total: 134)
        await eventually {
            if case .joined(_, 37, 134) = store.joinPhase { return true }
            return false
        }
    }

    func testJoiningWithTextThatIsNotATicketFails() async {
        let (store, _, _) = await make()
        await store.join(text: "hello")
        XCTAssertEqual(store.joinPhase, .failed(.notATicket))
        store.resetJoin()
        XCTAssertEqual(store.joinPhase, .idle)
    }

    func testJoiningWithAUsedTicketFails() async throws {
        let (store, peers, _) = await make()
        let ticket = try await peers.ticket(withAddresses: false)
        await store.join(text: ticket.text)
        await store.join(text: ticket.text)
        XCTAssertEqual(store.joinPhase, .failed(.usedOrExpired))
    }

    func testJoiningWithAnExpiredTicketFails() async throws {
        let (store, peers, clock) = await make()
        let ticket = try await peers.ticket(withAddresses: false)
        clock.advance(601)
        await store.join(text: ticket.text)
        XCTAssertEqual(store.joinPhase, .failed(.usedOrExpired))
    }

    func testJoiningAnUnreachableVaultFails() async throws {
        let (store, peers, _) = await make()
        let ticket = try await peers.ticket(withAddresses: false)
        await peers.setReachable(false)
        await store.join(text: ticket.text)
        XCTAssertEqual(store.joinPhase, .failed(.unreachable))
    }

    func testARedeemedTicketIsNoted() async throws {
        let (store, peers, _) = await make()
        await store.openTicket()
        let ticket = try XCTUnwrap(store.currentTicket)
        let device = try await peers.accept(ticket.text)
        await eventually { store.redeemedBy == device.id }
        await eventually { store.devices.contains(device) }
    }

    func testRemovingWithoutRotationKeepsTheKey() async throws {
        let (store, _, _) = await make()
        let target = store.devices[1]
        await store.remove(target.id, rotate: false)
        XCTAssertFalse(store.devices.contains { $0.id == target.id })
        XCTAssertNil(store.rotation)
    }

    func testRemovingWithRotationShowsProgress() async throws {
        let (store, _, _) = await make()
        let target = store.devices[1]
        await store.remove(target.id, rotate: true)
        XCTAssertFalse(store.devices.contains { $0.id == target.id })
        let rotation = try XCTUnwrap(store.rotation)
        XCTAssertEqual(rotation.total, 3)
        XCTAssertEqual(rotation.done, 3)
        XCTAssertEqual(rotation.result, RotationResult(reached: 3, missed: []))
        store.dismissRotation()
        XCTAssertNil(store.rotation)
    }

    func testRotationNamesTheDeviceThatMissed() async throws {
        let (store, peers, _) = await make()
        let missing = store.devices[3].id
        await peers.setMissing([missing])
        await store.remove(store.devices[1].id, rotate: true)
        XCTAssertEqual(store.rotation?.result, RotationResult(reached: 2, missed: [missing]))
        XCTAssertEqual(store.devices.first { $0.id == missing }?.missed, true)
    }

    func testAllowingAMissedDeviceClearsIt() async {
        let (store, peers, _) = await make()
        let id = store.devices[2].id
        await peers.setMissing([id])
        await store.remove(store.devices[1].id, rotate: true)
        await store.allow(id)
        XCTAssertEqual(store.devices.first { $0.id == id }?.missed, false)
    }

    func testARotationThatLeftADeviceBehindNotesWhen() async throws {
        let (store, peers, clock) = await make()
        XCTAssertNil(store.rotatedAt)
        await peers.setMissing([store.devices[3].id])
        await store.remove(store.devices[1].id, rotate: true)
        XCTAssertEqual(store.rotatedAt, clock.now)
    }

    func testRemovingWithoutRotationNotesNoTime() async throws {
        let (store, _, _) = await make()
        await store.remove(store.devices[1].id, rotate: false)
        XCTAssertNil(store.rotatedAt)
    }

    func testTheRelayIsReadAndChanged() async throws {
        let (store, peers, _) = await make()
        XCTAssertEqual(store.relay, .default)
        await store.setRelay(.off)
        XCTAssertEqual(store.relay, .off)
        let stored = try await peers.relay()
        XCTAssertEqual(stored, .off)
        let url = URL(string: "https://relay.example.com")!
        await store.setRelay(.custom(url))
        XCTAssertEqual(store.relay, .custom(url))
    }
}

extension DeviceStoreTests {
    func testARefusedRemovalStartsNoRotation() async {
        let clock = TestClock()
        let peers = MemoryPeers(now: { clock.now })
        let store = DeviceStore(peers: peers, now: { clock.now })
        await store.start()
        var finished: [RotationResult] = []
        store.onRotationFinished = { finished.append($0) }
        let removed = await store.remove("nobody", rotate: true)
        XCTAssertFalse(removed)
        XCTAssertNil(store.rotation)
        XCTAssertTrue(finished.isEmpty)
        XCTAssertEqual(store.devices.count, 5)
    }

    func testARotationReportsEachDeviceAndTellsTheEnd() async throws {
        let clock = TestClock()
        let peers = MemoryPeers(missing: [MemoryPeers.fixtures()[3].id], now: { clock.now })
        let store = DeviceStore(peers: peers, now: { clock.now })
        await store.start()
        var finished: [RotationResult] = []
        store.onRotationFinished = { finished.append($0) }
        await store.rotateKey()
        let rotation = try XCTUnwrap(store.rotation)
        XCTAssertEqual(rotation.total, 4)
        XCTAssertEqual(rotation.reports[MemoryPeers.fixtures()[1].id], true)
        XCTAssertEqual(rotation.reports[MemoryPeers.fixtures()[3].id], false)
        XCTAssertEqual(finished, [RotationResult(reached: 3, missed: [MemoryPeers.fixtures()[3].id])])
        XCTAssertEqual(DevicesText.rotationCount(rotation), "4 of 5")
    }

    func testARotationTheNodeCannotStartSaysItFailed() async {
        let (store, peers, _) = await make()
        await peers.setRotationFails(true)
        var finished: [RotationResult] = []
        store.onRotationFinished = { finished.append($0) }
        await store.rotateKey()
        XCTAssertNil(store.rotation)
        XCTAssertNil(store.rotatedAt)
        XCTAssertEqual(finished, [RotationResult(reached: 0, missed: [], failed: true)])
        XCTAssertEqual(DevicesText.rotated(finished[0]), "Couldn't rotate the key · the old one still works")
    }

    func testANewNodeReplacesTheTicketAndRequestOnShow() async throws {
        let (store, _, clock) = await make()
        await store.openTicket()
        await store.openRequest()
        let ticket = try XCTUnwrap(store.currentTicket)
        let request = try XCTUnwrap(store.currentRequest)
        clock.advance(60)
        await store.use(MemoryPeers(now: { clock.now }))
        XCTAssertEqual(store.currentTicket?.madeAt, ticket.madeAt.addingTimeInterval(60), "a ticket from the node in charge")
        XCTAssertEqual(store.currentRequest?.madeAt, request.madeAt.addingTimeInterval(60))
        store.closeTicket()
        store.closeRequest()
        await store.use(MemoryPeers(now: { clock.now }))
        XCTAssertNil(store.currentTicket, "a closed sheet stays closed")
        XCTAssertNil(store.currentRequest)
    }

    func testASyncThatFinishedIsReported() async {
        let clock = TestClock()
        let peers = MemoryPeers(now: { clock.now })
        let store = DeviceStore(peers: peers, now: { clock.now })
        await store.start()
        var summaries: [SyncSummary] = []
        store.onSyncFinished = { summaries.append($0) }
        let summary = SyncSummary(created: 2, updated: 1, ops: 3)
        await peers.setNextSummary(summary)
        await store.syncNow()
        await eventually { summaries == [summary] }
    }


    func testTheRequestColumnGetsARequestAndRefreshesItOnExpiry() async throws {
        let (store, _, clock) = await make()
        await store.openRequest()
        let first = try XCTUnwrap(store.currentRequest)
        XCTAssertEqual(first.words.count, 6)
        await store.refreshRequestIfExpired()
        XCTAssertEqual(store.currentRequest, first, "fresh, so kept")
        clock.advance(JoinRequest.lifetime + 1)
        await store.refreshRequestIfExpired()
        XCTAssertNotEqual(store.currentRequest, first)
        store.closeRequest()
        XCTAssertNil(store.currentRequest)
        await store.refreshRequestIfExpired()
        XCTAssertNil(store.currentRequest, "closed, so none")
    }

    func testADeviceBringingTheKeyWhileTheRequestIsOpenStartsTheFirstFetch() async throws {
        let (store, peers, _) = await make()
        await store.openRequest()
        let request = try XCTUnwrap(store.currentRequest)
        // The phone, from its side, confirms the words and brings the key.
        let phone = try await peers.confirmRequest(request.code)
        await eventually { store.joinPhase == .joined(phone, received: 0, total: nil) }
        XCTAssertNil(store.currentRequest, "the request is done with")
        await peers.emitFetchProgress(received: 3, total: 7)
        await eventually { store.joinPhase == .joined(phone, received: 3, total: 7) }
    }

    func testTheOfferIsShownAndARefusalKeepsTheRequestUp() async throws {
        let (store, peers, _) = await make()
        await store.openRequest()
        let request = try XCTUnwrap(store.currentRequest)
        await peers.offerJoin(kind: .iphone, name: "Ada’s iPhone")
        await eventually { store.offer != nil }
        XCTAssertEqual(store.offer?.words, request.words)
        await store.answerJoin(keep: false)
        XCTAssertNil(store.offer)
        XCTAssertEqual(store.currentRequest, request, "the code stays up")
        XCTAssertEqual(store.joinPhase, .idle)
        await peers.offerJoin()
        await eventually { store.offer != nil }
        await store.answerJoin(keep: true)
        await eventually {
            if case .joined = store.joinPhase { return true }
            return false
        }
        XCTAssertNil(store.currentRequest)
        XCTAssertNil(store.offer)
    }

    func testAnOfferWithNoRequestOpenIsNotShown() async throws {
        let (store, peers, _) = await make()
        await peers.offerJoin()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(store.offer)
    }

    func testAJoinedDeviceWithNoRequestOpenOnlyRefreshes() async throws {
        let (store, peers, _) = await make()
        let request = try await peers.joinRequest()
        _ = try await peers.confirmRequest(request.code)
        await eventually { store.devices.count == 6 }
        XCTAssertEqual(store.joinPhase, .idle)
    }

    func testThePhoneReadsTheWordsThenConfirmsAndTheDeviceIsListed() async throws {
        let (store, peers, _) = await make()
        let request = try await peers.joinRequest()
        await store.readRequest(request.code)
        XCTAssertEqual(store.requestPhase, .words(request.words, code: request.code))
        await store.confirmRequest()
        guard case let .confirmed(device) = store.requestPhase else { return XCTFail("\(store.requestPhase)") }
        XCTAssertTrue(store.devices.contains(device))
        store.resetRequest()
        XCTAssertEqual(store.requestPhase, .idle)
        await store.confirmRequest()
        XCTAssertEqual(store.requestPhase, .idle, "nothing to confirm without words")
    }

    func testAReadOrConfirmationThatEndsAfterAResetIsDropped() async throws {
        let (store, peers, _) = await make()
        let request = try await peers.joinRequest()
        await store.readRequest(request.code)
        await peers.setAutoAnswer(nil)
        let confirming = Task { await store.confirmRequest() }
        await eventually { store.requestPhase == .confirming }
        store.resetRequest()
        // The memory TV puts the offer up a moment after the call reaches it.
        var answered = false
        for _ in 0..<400 where !answered {
            do {
                try await peers.answerJoin(keep: true)
                answered = true
            } catch {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
        }
        XCTAssertTrue(answered)
        await confirming.value
        XCTAssertEqual(store.requestPhase, .idle, "the closed sheet's answer is not shown")
    }

    func testAReadThatEndsAfterAResetIsDropped() async throws {
        let (store, peers, _) = await make()
        let request = try await peers.joinRequest()
        await peers.setReadDelay(0.1)
        let reading = Task { await store.readRequest(request.code) }
        await eventually { store.requestPhase == .reading }
        store.resetRequest()
        await reading.value
        XCTAssertEqual(store.requestPhase, .idle, "the closed sheet's words are not shown")
    }

    func testAFailedRequestNamesWhy() async throws {
        let (store, peers, _) = await make()
        await store.readRequest("bud1 a ticket")
        XCTAssertEqual(store.requestPhase, .failed(.notARequest))
        let request = try await peers.joinRequest()
        await peers.setRequestFailure(.expired)
        await store.readRequest(request.code)
        XCTAssertEqual(store.requestPhase, .failed(.expired))
        await peers.setRequestFailure(nil)
        await store.readRequest(request.code)
        await peers.setRequestFailure(.refused)
        await store.confirmRequest()
        XCTAssertEqual(store.requestPhase, .failed(.refused))
    }

    func testTheRequestErrorReadsTheCoreMessages() {
        XCTAssertEqual(RequestError(message: "Invalid: not a join request: wrong start"), .notARequest)
        XCTAssertEqual(RequestError(message: "peer: that request is past its lifetime"), .expired)
        XCTAssertEqual(RequestError(message: "peer: that request is this vault's"), .expired)
        XCTAssertEqual(RequestError(message: "peer: the device did not answer"), .unreachable)
        XCTAssertEqual(RequestError(message: "peer: the device did not confirm the key"), .refused)
        XCTAssertEqual(RequestError(message: "peer: the device refused the key"), .refused)
        XCTAssertEqual(RequestError(message: "peer: this vault is paired with another vault already"), .refused)
        XCTAssertNil(RequestError(message: "something else"))
    }
}
