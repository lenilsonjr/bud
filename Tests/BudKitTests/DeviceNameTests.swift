import XCTest
@testable import BudKit

final class DeviceNameTests: XCTestCase {
    func testTheDisplayNamePrefersTheLabelThenTheName() {
        var device = Device(id: "a91cp4x8d2n6w0j3h5v9b1m7r2ks7t0e")
        XCTAssertNil(device.displayName, "nothing sent, nothing given: the row shows the id")
        device.name = "Living room"
        XCTAssertEqual(device.displayName, "Living room")
        device.label = "  The big screen "
        XCTAssertEqual(device.displayName, "The big screen", "the label wins, trimmed")
        device.label = "   "
        XCTAssertEqual(device.displayName, "Living room", "a blank label is none")
    }

    func testRenamingADeviceInMemorySticksAndAnEmptyLabelClearsIt() async throws {
        let peers = MemoryPeers(devices: [Device(id: "one", name: "Study", kind: .mac)])
        try await peers.rename("one", label: "Desk")
        var devices = try await peers.devices()
        XCTAssertEqual(devices.first?.label, "Desk")
        try await peers.rename("one", label: "")
        devices = try await peers.devices()
        XCTAssertNil(devices.first?.label)
        do {
            try await peers.rename("two", label: "x")
            XCTFail("an unknown device is an error")
        } catch PeersError.noSuchDevice(let id) {
            XCTAssertEqual(id, "two")
        }
    }
}
