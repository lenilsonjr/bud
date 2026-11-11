import XCTest
@testable import BudKit

#if canImport(SwiftUI)
import SwiftUI

/// What every picture shares, on the Mac and in the iOS app: the one moment it is taken at, the
/// seed world on that clock, and the folder `BUD_SNAPSHOT_DIR` names.
extension XCTestCase {
    /// The one moment every picture is taken at, so two runs draw the same days and counts.
    var stillClock: @Sendable () -> Date { { Tree.stillNow } }

    /// A device store on the fixed clock with no peers, the one every still picture reads.
    @MainActor
    func stillDevices() -> DeviceStore {
        DeviceStore(peers: MemoryPeers.forLaunch(arguments: [], now: stillClock), now: stillClock)
    }

    /// The one layout every picture reads its keys from, as the clock is one moment: the table's
    /// defaults and nothing recorded over them, whatever the process's defaults hold.
    var stillKeys: KeyLayout { StillKeys.layout }

    /// The seed world on the fixed clock, which the store reads from its device store, with the
    /// still keys.
    @MainActor
    func stillStore(devices: DeviceStore? = nil) -> BudStore {
        BudStore(fileURL: nil, devices: devices ?? stillDevices(), keys: stillKeys)
    }

    /// Choices of a picture's own on the flags' suite, drawn always light or always dark as the
    /// picture is, so the appearance the person or the host app chose never reaches it.
    @MainActor
    func stillFlags(_ scheme: ColorScheme) -> Flags {
        let flags = Flags(defaults: StillFlags.defaults)
        flags.appearance = scheme == .dark ? .dark : .light
        return flags
    }
}

/// The still layout, on a defaults suite named for this process alone, so two stores in one test
/// share it and two runs side by side never share a file. The suite is wiped when the layout is
/// made and again when the process ends; no picture records into it.
enum StillKeys {
    static let suite = "bud.still.\(UUID().uuidString)"

    static let layout: KeyLayout = {
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("No defaults suite named \(suite)") }
        defaults.removePersistentDomain(forName: suite)
        atexit { UserDefaults(suiteName: StillKeys.suite)?.removePersistentDomain(forName: StillKeys.suite) }
        return KeyLayout(defaults: defaults)
    }()
}

/// Where a picture's flags keep its appearance: a suite of their own beside the still layout's,
/// named for this process alone and wiped when it is opened and again when the process ends.
enum StillFlags {
    static let suite = "bud.still.flags.\(UUID().uuidString)"

    static let defaults: UserDefaults = {
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("No defaults suite named \(suite)") }
        defaults.removePersistentDomain(forName: suite)
        atexit { UserDefaults(suiteName: StillFlags.suite)?.removePersistentDomain(forName: StillFlags.suite) }
        return defaults
    }()
}

extension XCTestCase {
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
}
#endif

#if canImport(SwiftUI) && os(macOS)
import AppKit
import SwiftUI

/// One frame rendered under a light or dark appearance, and the picture as PNG.
extension XCTestCase {
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
