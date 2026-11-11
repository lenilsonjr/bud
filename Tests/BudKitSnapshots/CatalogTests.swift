import XCTest
@testable import BudKit

#if canImport(SwiftUI) && os(macOS)
import AppKit
import SnapshotTesting
import SwiftUI

/// Every screen against a reference picture committed next to this file, under `__Snapshots__`.
/// The screens are `Catalog.screens`, the table the iOS app's catalog reads too. Each state is set through the store, never by a tap, and rendered at one pixel per point so
/// the whole set stays small. A missing reference is recorded and fails the run; a screen that
/// no longer matches fails with the reference and a difference image beside it. Every picture
/// taken lands in `catalog` inside `BUD_SNAPSHOT_DIR`, with `manifest.txt` saying what became
/// of each screen, so the run's artifact carries the whole catalog and what changed in it. Like
/// the other pictures, the catalog only runs when `BUD_SNAPSHOT_DIR` is set.
///
/// `BUD_CATALOG_REFERENCES` points the run at another folder of references, which is how
/// `scripts/compare-screens.sh` holds the working tree against the pictures of an older ref.
@MainActor
final class CatalogTests: XCTestCase {
    /// A pixel matches its reference when it is within the perceptual tolerance, which covers
    /// antialiasing noise between runs. Five pixels in a hundred thousand may stray beyond it:
    /// about 17 on the phone window and 63 on the Mac window. That absorbs the eight pixels on
    /// one row where the help button's top edge meets the modal card's bottom edge under the
    /// scrim in the phone settings pictures (modal.settings-phone-light and -dark), which
    /// rasterize differently from one run to the next, while a control with more than about 60
    /// pixels of edge that moves by a pixel still fails.
    private let strategy = Snapshotting<NSImage, NSImage>.image(precision: 0.99995, perceptualPrecision: 0.98)

    /// Another folder of references to compare against, when `BUD_CATALOG_REFERENCES` names one.
    private static let otherReferences: URL? = {
        guard let dir = ProcessInfo.processInfo.environment["BUD_CATALOG_REFERENCES"], !dir.isEmpty else { return nil }
        return URL(fileURLWithPath: dir, isDirectory: true)
    }()

    /// The reference pictures: the other folder when there is one, else the library's folder
    /// beside this file, one file per screen.
    private static let references = otherReferences ?? URL(fileURLWithPath: #filePath, isDirectory: false)
        .deletingLastPathComponent()
        .appendingPathComponent("__Snapshots__", isDirectory: true)
        .appendingPathComponent("CatalogTests", isDirectory: true)

    /// Every shot on its own: one that cannot be set up or rendered fails naming the screen and
    /// the rest still run, so one run reports every broken screen.
    func testEveryScreenMatchesItsReference() throws {
        let out = try pictureFolder("catalog")
        let catalog = Catalog.screens
        for screen in catalog {
            for shot in screen.shots { try Catalog.note(screen.name(shot), .planned, in: out) }
        }
        for screen in catalog {
            for shot in screen.shots {
                let name = screen.name(shot)
                do {
                    let store = stillStore()
                    store.sidebar = SidebarVisibility(followsWindow: shot.window.followsWindow)
                    try screen.prepare(store)
                    let image = try render(store: store, in: shot.window, scheme: shot.scheme)
                    try check(image, surface: screen.surface, name: "\(screen.state)-\(shot.name)", into: out)
                } catch {
                    try Catalog.note(name, .failed, in: out)
                    XCTFail("\(name) could not be taken: \(error)")
                    continue
                }
            }
        }
    }

    /// The phone palette on its own, as `Catalog.phonePalette` says.
    func testThePhonePaletteMatchesItsReference() throws {
        let out = try pictureFolder("catalog")
        let names = Catalog.phonePalette
        for (_, name) in names { try Catalog.note("modal.\(name)", .planned, in: out) }
        let store = stillStore()
        store.sidebar = SidebarVisibility(followsWindow: true)
        for (scheme, name) in names {
            let sheet = CommandPalette(store: store, inSheet: true) { store.searching = false }
                .frame(width: Catalog.phonePaletteSize.width, height: Catalog.phonePaletteSize.height)
                .background(Theme.raised)
                .environment(\.compact, true)
            let image = try stillImage(sheet, scheme: scheme, scale: 1)
            try check(image, surface: "modal", name: name, into: out)
        }
    }

    // MARK: Comparing

    /// One picture against its reference. The picture as taken always lands in `out`. A
    /// mismatch, a reference that cannot be read as a picture, or one that had to be recorded
    /// fails the test naming the screen, and leaves the reference and the difference beside it.
    private func check(_ image: NSImage, surface: String, name: String, into out: URL) throws {
        let screen = "\(surface).\(name)"
        let reference = Self.references.appendingPathComponent("\(screen).png")
        let taken = out.appendingPathComponent("\(screen).png")
        try png(image).write(to: taken)
        // Read before the library runs: in its record modes it overwrites the reference.
        let old = NSImage(contentsOf: reference)
        if old == nil, FileManager.default.fileExists(atPath: reference.path) {
            // The library cannot decode it either, so it never sees the file. The screen counts
            // as changed, with the picture as taken standing in for the difference.
            try Data(contentsOf: reference).write(to: out.appendingPathComponent("\(screen).reference.png"))
            try png(image).write(to: out.appendingPathComponent("\(screen).diff.png"))
            try Catalog.note(screen, .mismatched, in: out)
            XCTFail("\(screen) has a reference that cannot be read as a picture; see catalog/\(screen).png")
            return
        }
        guard let failure = verifySnapshot(
            of: image, as: strategy, named: name, snapshotDirectory: Self.references.path, testName: surface)
        else { return try Catalog.note(screen, .matched, in: out) }
        if let old {
            try png(old).write(to: out.appendingPathComponent("\(screen).reference.png"))
            try png(difference(old, image)).write(to: out.appendingPathComponent("\(screen).diff.png"))
            try Catalog.note(screen, .mismatched, in: out)
            XCTFail("\(screen) does not match its reference; see catalog/\(screen).diff.png. \(failure)")
        } else {
            try Catalog.note(screen, .recorded, in: out)
            XCTFail("\(screen) had no reference; recorded one. \(failure)")
        }
    }

    /// Where the two pictures differ, pixel for pixel at the reference's own size: black where
    /// they agree, the difference in colour elsewhere.
    private func difference(_ old: NSImage, _ new: NSImage) throws -> NSImage {
        let oldPixels = try XCTUnwrap(old.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let newPixels = try XCTUnwrap(new.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let width = max(oldPixels.width, newPixels.width), height = max(oldPixels.height, newPixels.height)
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = CGSize(width: width, height: height)
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.draw(oldPixels, in: CGRect(x: 0, y: 0, width: oldPixels.width, height: oldPixels.height))
        context.cgContext.setBlendMode(.difference)
        context.cgContext.draw(newPixels, in: CGRect(x: 0, y: 0, width: newPixels.width, height: newPixels.height))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: Rendering

    private func render(store: BudStore, in window: Catalog.Window, scheme: ColorScheme) throws -> NSImage {
        let view = BudRootView(store: store)
            .frame(width: window.size.width, height: window.size.height)
            .environment(\.compact, window.compact)
        return try stillImage(view, scheme: scheme, scale: 1)
    }
}
#endif
