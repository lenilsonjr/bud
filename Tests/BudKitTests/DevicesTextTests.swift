import XCTest
@testable import BudKit

final class DevicesTextTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testThisDeviceNamesFollowThePlatform() {
        XCTAssertEqual(DevicesText.thisDevice(.mac), "This Mac")
        XCTAssertEqual(DevicesText.thisDevice(.iphone), "This iPhone")
        XCTAssertEqual(DevicesText.thisDevice(.ipad), "This iPad")
        XCTAssertEqual(DevicesText.thisDevice(.tv), "This Apple TV")
        XCTAssertEqual(DevicesText.thisDevice(nil), "This device")
    }

    func testTheDeviceWordFollowsThePlatform() {
        XCTAssertEqual(DevicesText.deviceWord(.mac), "Mac")
        XCTAssertEqual(DevicesText.deviceWord(.iphone), "iPhone")
        XCTAssertEqual(DevicesText.deviceWord(.ipad), "iPad")
        XCTAssertEqual(DevicesText.deviceWord(nil), "device")
    }

    func testThisDeviceComesFirstAndTheRestKeepTheirOrder() {
        let a = Device(id: "a")
        let b = Device(id: "b", isThisDevice: true)
        let c = Device(id: "c")
        XCTAssertEqual(DevicesText.ordered([a, b, c]).map(\.id), ["b", "a", "c"])
    }

    func testOnlyThisDeviceMeansNoDevicesYet() {
        XCTAssertTrue(DevicesText.isEmpty([Device(id: "a", isThisDevice: true)]))
        XCTAssertTrue(DevicesText.isEmpty([]))
        XCTAssertFalse(DevicesText.isEmpty([Device(id: "a", isThisDevice: true), Device(id: "b")]))
    }

    func testNoticeNamesTheTimeAndTheCount() {
        // 1_800_000_000 is 08:00 UTC; 10:42 is 2 hours 42 minutes later.
        let since = Date(timeIntervalSince1970: 1_800_000_000 + 9_720)
        XCTAssertEqual(
            DevicesText.notice(missed: 1, since: since, timeZone: utc),
            "New key since 10:42. 1 device missed it and needs a fresh ticket.")
        XCTAssertEqual(
            DevicesText.notice(missed: 2, since: since, timeZone: utc),
            "New key since 10:42. 2 devices missed it and need a fresh ticket.")
    }

    func testNoticeWithoutATimeAndWithoutMisses() {
        XCTAssertEqual(
            DevicesText.notice(missed: 1, since: nil, timeZone: utc),
            "New key. 1 device missed it and needs a fresh ticket.")
        XCTAssertNil(DevicesText.notice(missed: 0, since: now, timeZone: utc))
    }

    func testRelayChoices() {
        XCTAssertEqual(RelayChoice.allCases.map(\.title), ["Public relays", "Custom by URL", "Off"])
        XCTAssertEqual(RelayChoice(.default), .publicRelays)
        XCTAssertEqual(RelayChoice(.custom(URL(string: "https://relay.example.com")!)), .custom)
        XCTAssertEqual(RelayChoice(.off), .off)
    }

    func testCustomRelayURLNeedsAHost() {
        XCTAssertEqual(RelayChoice.url(from: " https://relay.example.com "), URL(string: "https://relay.example.com"))
        XCTAssertNil(RelayChoice.url(from: "relay.example.com"))
        XCTAssertNil(RelayChoice.url(from: "https://"))
        XCTAssertNil(RelayChoice.url(from: "ftp://relay.example.com"))
        XCTAssertNil(RelayChoice.url(from: ""))
    }

    func testDeviceModalsHaveTheirOwnIdentity() {
        XCTAssertNotEqual(Modal.showTicket.id, Modal.joinVault.id)
        XCTAssertNotEqual(Modal.showTicket.id, Modal.settings.id)
    }
}

extension DevicesTextTests {
    func testTheRowCaptionSaysHowADeviceIsReached() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let mine = Device(id: "a", isThisDevice: true, reach: .local, lastSeen: now)
        XCTAssertEqual(DevicesText.rowCaption(mine, kind: .mac, now: now), "This Mac · holds the vault")
        let near = Device(id: "b", reach: .local, lastSeen: now.addingTimeInterval(-10))
        XCTAssertEqual(DevicesText.rowCaption(near, kind: .mac, now: now), "Local network · seen just now")
        let far = Device(id: "c", reach: .relay, lastSeen: now.addingTimeInterval(-2 * 3600))
        XCTAssertEqual(DevicesText.rowCaption(far, kind: .mac, now: now), "Through a relay · seen 2 hours ago")
        let direct = Device(id: "d", reach: .direct, lastSeen: now.addingTimeInterval(-86400))
        XCTAssertEqual(DevicesText.rowCaption(direct, kind: .mac, now: now), "Direct · seen 1 day ago")
        let never = Device(id: "e", reach: .relay)
        XCTAssertEqual(DevicesText.rowCaption(never, kind: .mac, now: now), "Through a relay · not seen yet")
        let missed = Device(id: "f", reach: .local, lastSeen: now, missed: true)
        XCTAssertEqual(DevicesText.rowCaption(missed, kind: .mac, now: now), "Missed the new key")
    }

    func testTheInvitationNamesTheOtherDevices() {
        XCTAssertEqual(DevicesText.alone(.mac), "Only this Mac has the vault so far")
        XCTAssertEqual(
            DevicesText.invitation(.mac),
            "Show a ticket here and take it on your iPhone, iPad or Apple TV. If your vault already lives on another device, add this Mac to it instead.")
        XCTAssertEqual(
            DevicesText.invitation(.iphone),
            "Show a ticket here and take it on your Mac, iPad or Apple TV. If your vault already lives on another device, add this iPhone to it instead.")
    }

    func testTheSyncToastCountsWhatArrived() {
        XCTAssertEqual(DevicesText.arrival(SyncSummary(created: 1, updated: 2, ops: 9)), "3 changes arrived")
        XCTAssertEqual(DevicesText.arrival(SyncSummary(moved: 1)), "1 change arrived")
        XCTAssertNil(DevicesText.arrival(SyncSummary(ops: 4)), "Ops alone bring nothing in")
    }

    func testTheRotationToastSaysWhoMissedIt() {
        XCTAssertEqual(DevicesText.rotated(RotationResult(reached: 2, missed: ["m"])), "Key rotated · 1 device missed it")
        XCTAssertEqual(DevicesText.rotated(RotationResult(reached: 1, missed: ["m", "t"])), "Key rotated · 2 devices missed it")
        XCTAssertEqual(DevicesText.rotated(RotationResult(reached: 3, missed: [])), "Key rotated · 3 devices got it")
    }

    func testTheRotationLinesFollowEachDevice() {
        let devices = [
            Device(id: "k7f3", reach: .direct),
            Device(id: "a91c", isThisDevice: true, reach: .local),
            Device(id: "m2pd", reach: .relay),
            Device(id: "t6vb", reach: .local),
        ]
        let progress = RotationProgress(total: 3, done: 2, reports: ["k7f3": true, "t6vb": false])
        let lines = DevicesText.rotationLines(devices, progress: progress, kind: .mac)
        XCTAssertEqual(lines.map(\.id), ["a91c", "k7f3", "m2pd", "t6vb"])
        XCTAssertEqual(lines.map(\.state), [.newKey, .gotIt, .waiting, .missed])
        XCTAssertEqual(lines.map(\.label), [
            "This Mac · new key", "Got it", "Waiting · apart, through a relay", "Didn’t answer · missed the new key",
        ])
        XCTAssertEqual(DevicesText.rotationCount(progress), "2 of 4")
        XCTAssertEqual(DevicesText.rotationCount(nil), "1 of 1")
        let local = DevicesText.rotationLines([Device(id: "x", reach: .local)], progress: nil, kind: .mac)
        XCTAssertEqual(local.first?.label, "Waiting · on the local network")
    }
}
