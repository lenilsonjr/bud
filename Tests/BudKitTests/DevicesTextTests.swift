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
