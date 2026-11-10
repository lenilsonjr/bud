import XCTest
@testable import BudKit

#if canImport(SwiftUI) && os(macOS)
import AppKit
import SwiftUI

/// What every picture shares: the one moment it is taken at, the seed world on that clock, the
/// folder `BUD_SNAPSHOT_DIR` names, and one frame rendered under a light or dark appearance.
extension XCTestCase {
    /// The one moment every picture is taken at, so two runs draw the same days and counts.
    var stillClock: @Sendable () -> Date { { Tree.stillNow } }

    /// A device store on the fixed clock with no peers, the one every still picture reads.
    @MainActor
    func stillDevices() -> DeviceStore {
        DeviceStore(peers: MemoryPeers.forLaunch(arguments: [], now: stillClock), now: stillClock)
    }

    /// The seed world on the fixed clock, which the store reads from its device store.
    @MainActor
    func stillStore(devices: DeviceStore? = nil) -> BudStore {
        BudStore(fileURL: nil, devices: devices ?? stillDevices())
    }

    /// The folder the pictures go to, created. Skips the test when `BUD_SNAPSHOT_DIR` is not
    /// set, so the gate on Linux and an ordinary `swift test` pass it by.
    func pictureFolder(_ name: String? = nil) throws -> URL {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        var folder = URL(fileURLWithPath: dir, isDirectory: true)
        if let name { folder.appendPathComponent(name, isDirectory: true) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// One frame at `scale` pixels per point, with no animation in flight, so a picture never
    /// lands mid-transition.
    @MainActor
    func stillImage(_ content: some View, scheme: ColorScheme, scale: CGFloat) throws -> NSImage {
        let view = content
            .environment(\.colorScheme, scheme)
            .environment(\.stillPicture, true)
            .transaction { $0.animation = nil }
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let appearance = try XCTUnwrap(NSAppearance(named: scheme == .dark ? .darkAqua : .aqua))
        var image: NSImage?
        appearance.performAsCurrentDrawingAppearance { image = renderer.nsImage }
        return try XCTUnwrap(image, "ImageRenderer produced no image")
    }

    /// The picture as PNG data, its pixels as rendered.
    func png(_ image: NSImage) throws -> Data {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = image.size
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
#endif
