import XCTest
@testable import BudKit

final class SyncIndicatorTests: XCTestCase {
    func testQuietWhenNothingIsConnectedAndNothingWaits() {
        XCTAssertEqual(SyncIndicator(nil), .quiet)
        XCTAssertEqual(SyncIndicator(SyncState(idle: true, connectedPeers: 0, pendingChanges: 0)), .quiet)
        XCTAssertFalse(SyncIndicator.quiet.isShown)
        XCTAssertEqual(SyncIndicator.quiet.label, "")
    }

    func testConnectedIsADotWithTheDeviceCount() {
        let one = SyncIndicator(SyncState(idle: true, connectedPeers: 1, pendingChanges: 0))
        XCTAssertEqual(one, .connected(devices: 1))
        XCTAssertNil(one.count)
        XCTAssertFalse(one.isHollow)
        XCTAssertEqual(one.label, "1 device connected")
        XCTAssertEqual(SyncIndicator(SyncState(idle: true, connectedPeers: 2, pendingChanges: 0)).label, "2 devices connected")
    }

    func testPendingCountsChangesNotDevices() {
        let pending = SyncIndicator(SyncState(idle: true, connectedPeers: 2, pendingChanges: 3))
        XCTAssertEqual(pending, .pending(changes: 3, devices: 2))
        XCTAssertEqual(pending.count, 3)
        XCTAssertFalse(pending.isHollow)
        XCTAssertEqual(pending.label, "2 devices connected · 3 changes waiting to go out")
        XCTAssertEqual(SyncIndicator(SyncState(idle: true, connectedPeers: 1, pendingChanges: 1)).label, "1 device connected · 1 change waiting to go out")
    }

    func testPendingApartIsHollowWhenNobodyIsConnected() {
        let apart = SyncIndicator(SyncState(idle: true, connectedPeers: 0, pendingChanges: 3))
        XCTAssertEqual(apart, .pendingApart(changes: 3))
        XCTAssertEqual(apart.count, 3)
        XCTAssertTrue(apart.isHollow)
        XCTAssertEqual(apart.label, "3 changes waiting to go out · no device connected")
    }

    func testSyncingWinsWhileASyncRuns() {
        let busy = SyncIndicator(SyncState(idle: false, connectedPeers: 2, pendingChanges: 3))
        XCTAssertEqual(busy, .syncing(devices: 2))
        XCTAssertNil(busy.count)
        XCTAssertEqual(busy.label, "Syncing with 2 devices")
        XCTAssertEqual(SyncIndicator(SyncState(idle: false, connectedPeers: 0, pendingChanges: 0)).label, "Syncing")
    }
}
