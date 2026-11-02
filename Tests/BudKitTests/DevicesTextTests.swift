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

    func testArrivedCountsFromTheSummary() {
        XCTAssertEqual(DevicesText.arrived(SyncSummary(ops: 3)), "3 changes arrived")
        XCTAssertEqual(DevicesText.arrived(SyncSummary(ops: 1)), "1 change arrived")
        XCTAssertEqual(DevicesText.arrived(SyncSummary(created: 2, updated: 1, written: 3)), "3 changes arrived")
        XCTAssertNil(DevicesText.arrived(SyncSummary()))
    }

    func testRotationCount() {
        XCTAssertEqual(DevicesText.count(RotationProgress(total: 3, done: 2)), "2 of 3")
        XCTAssertEqual(DevicesText.count(RotationProgress(total: 0)), "0 of 0")
    }

    func testRotationLinesFollowWhatTheCoreReports() {
        let devices = [
            Device(id: "a", isThisDevice: true), Device(id: "k7f3c8z1q5t3y7u0e4i6o2a9l5gdq2m9"),
            Device(id: "m2pdx3v7n1b5c9z2l6k0j4h8g3fsh81k"),
        ]
        var progress = RotationProgress(total: 2)
        XCTAssertEqual(
            DevicesText.rotationLines(progress, devices: devices),
            [DevicesText.RotationLine(id: "single", text: "Giving the new key to 2 devices")])
        progress.reports = [.init(id: "k7f3c8z1q5t3y7u0e4i6o2a9l5gdq2m9", reached: true)]
        progress.done = 1
        XCTAssertEqual(
            DevicesText.rotationLines(progress, devices: devices).map(\.text),
            ["k7f3…q2m9 has the new key"])
        progress.reports.append(.init(id: "m2pdx3v7n1b5c9z2l6k0j4h8g3fsh81k", reached: false))
        XCTAssertEqual(
            DevicesText.rotationLines(progress, devices: devices).map(\.text),
            ["k7f3…q2m9 has the new key", "m2pd…h81k did not answer"])
    }

    func testRotationResultLine() {
        XCTAssertEqual(
            DevicesText.result(RotationResult(reached: 3, missed: [])), "New key on all 3 devices.")
        XCTAssertEqual(
            DevicesText.result(RotationResult(reached: 2, missed: ["x"])),
            "New key on 2 devices. 1 device missed it and needs a fresh ticket.")
        XCTAssertEqual(
            DevicesText.result(RotationResult(reached: 0, missed: [])), "New key made. No other device to give it to.")
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
        XCTAssertNotEqual(Modal.rotateKey.id, Modal.removeDevice(id: "a").id)
        XCTAssertNotEqual(Modal.removeDevice(id: "a").id, Modal.removeDevice(id: "b").id)
        XCTAssertEqual(Modal.removeDevice(id: "a").id, Modal.removeDevice(id: "a").id)
    }
}
