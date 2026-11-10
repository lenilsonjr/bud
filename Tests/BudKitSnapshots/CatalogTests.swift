import XCTest
@testable import BudKit

#if canImport(SwiftUI) && os(macOS)
import AppKit
import SnapshotTesting
import SwiftUI

/// Every screen against a reference picture committed next to this file, under `__Snapshots__`.
/// Each state is set through the store, never by a tap, and rendered at one pixel per point so
/// the whole set stays small. A missing reference is recorded and fails the run; a screen that
/// no longer matches fails with the new picture, the reference and a difference image written to
/// `catalog` inside `BUD_SNAPSHOT_DIR`, so the run's artifact carries what changed. Like the
/// other pictures, the catalog only runs when `BUD_SNAPSHOT_DIR` is set.
@MainActor
final class CatalogTests: XCTestCase {
    /// A window the catalog renders in: its name in the file, its size in points, whether it is
    /// a compact width, and whether the sidebars follow the window's shape as they do on iOS.
    struct Window {
        let name: String
        let size: CGSize
        let compact: Bool
        let followsWindow: Bool

        static let mac = Window(name: "mac", size: CGSize(width: 1400, height: 900), compact: false, followsWindow: false)
        static let phone = Window(name: "phone", size: CGSize(width: 393, height: 852), compact: true, followsWindow: true)
        static let padPortrait = Window(name: "ipad-portrait", size: CGSize(width: 834, height: 1210), compact: false, followsWindow: true)
        static let padLandscape = Window(name: "ipad-landscape", size: CGSize(width: 1210, height: 834), compact: false, followsWindow: true)
        static let stageNarrow = Window(name: "stage-320x700", size: CGSize(width: 320, height: 700), compact: true, followsWindow: true)
        static let stageMedium = Window(name: "stage-600x800", size: CGSize(width: 600, height: 800), compact: true, followsWindow: true)
        static let stageWide = Window(name: "stage-1024x768", size: CGSize(width: 1024, height: 768), compact: false, followsWindow: true)

        /// The iPad both ways and the three Stage Manager windows, for the two screens that must
        /// hold up in all of them.
        static let pads: [Window] = [padPortrait, padLandscape, stageNarrow, stageMedium, stageWide]
    }

    /// One picture to take: the window and the appearance.
    struct Shot {
        let window: Window
        let scheme: ColorScheme

        var name: String { "\(window.name)-\(scheme == .dark ? "dark" : "light")" }

        static func both(_ windows: [Window]) -> [Shot] {
            windows.flatMap { [Shot(window: $0, scheme: .light), Shot(window: $0, scheme: .dark)] }
        }

        static func light(_ windows: [Window]) -> [Shot] {
            windows.map { Shot(window: $0, scheme: .light) }
        }
    }

    /// One screen: the surface it belongs to, its state, the shots to take, and how to put the
    /// store into that state.
    struct Screen {
        let surface: String
        let state: String
        let shots: [Shot]
        let prepare: @MainActor (BudStore) throws -> Void
    }

    /// A pixel matches its reference when it is within the perceptual tolerance, which covers
    /// antialiasing noise between runs. Five pixels in a hundred thousand may stray beyond it:
    /// about 17 on the phone window and 63 on the Mac window. That absorbs the eight pixels on
    /// one row where the help button's top edge meets the modal card's bottom edge under the
    /// scrim in the phone settings pictures (modal.settings-phone-light and -dark), which
    /// rasterize differently from one run to the next, while a control with more than about 60
    /// pixels of edge that moves by a pixel still fails.
    private let strategy = Snapshotting<NSImage, NSImage>.image(precision: 0.99995, perceptualPrecision: 0.98)

    /// The reference pictures: the library's folder beside this file, one file per screen.
    private static let references = URL(fileURLWithPath: #filePath, isDirectory: false)
        .deletingLastPathComponent()
        .appendingPathComponent("__Snapshots__", isDirectory: true)
        .appendingPathComponent("CatalogTests", isDirectory: true)

    // MARK: The catalog

    private var catalog: [Screen] {
        [
            Screen(surface: "canvas", state: "hub", shots: Shot.both([.mac, .phone]) + Shot.light(Window.pads)) { _ in },
            Screen(surface: "canvas", state: "thread", shots: Shot.both([.mac]) + Shot.light([.phone])) { store in
                let thread = try Self.newsletter(in: store)
                let deep = try XCTUnwrap(store.tree.children(of: thread.id).first)
                // One done to-do, so the picture shows the struck title and the filled check.
                if let leaf = store.tree.children(of: deep.id).first(where: { $0.isTodo }) { store.toggle(leaf.id) }
                store.center = thread.id
            },
            Screen(surface: "canvas", state: "lens", shots: Shot.both([.mac]) + Shot.light([.phone])) { store in
                for bud in store.tree.walk(under: rootID).filter({ $0.state == .open }).prefix(3) { store.addTag(bud.id, "home") }
                store.canvasFacets = [.openTodos, .tag("home")]
            },
            Screen(surface: "files", state: "page", shots: Shot.both([.mac, .phone]) + Shot.light(Window.pads)) { store in
                let name = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.text == "Pick a name" })
                store.setBody(name.id, "## What matters\n\nShort, warm, and easy to say out loud. Nothing with **club** in it.\n\n- Ask two readers\n- Check the domain is free")
                store.addTag(name.id, "brand")
                if let done = store.tree.children(of: name.id).first(where: { $0.isTodo }) { store.toggle(done.id) }
                store.openAsFile(name.id)
            },
            Screen(surface: "files", state: "sidebars-hidden", shots: Shot.light([.mac])) { store in
                store.openAsFile(try Self.newsletter(in: store).id)
                store.sidebar.toggle(.left, in: Window.mac.size)
                store.sidebar.toggle(.right, in: Window.mac.size)
            },
            Screen(surface: "files", state: "sidebar-shown", shots: Shot.light([.phone])) { store in
                store.openAsFile(try Self.newsletter(in: store).id)
                store.sidebar.toggle(.left, in: Window.phone.size)
            },
            Screen(surface: "files", state: "today", shots: Shot.both([.mac])) { store in
                store.open(.today)
            },
            Screen(surface: "files", state: "inbox", shots: Shot.light([.mac, .phone])) { store in
                store.openInbox()
            },
            Screen(surface: "files", state: "warehouse", shots: Shot.light([.mac])) { store in
                let thread = try Self.newsletter(in: store)
                let template = try XCTUnwrap(store.add("Weekly review", todo: true, under: thread.id))
                for step in ["Clear the inbox", "Look at next week", "Pick three things"] {
                    store.add(step, todo: true, under: template.id)
                }
                store.keepAsTemplate(template.id)
                store.toasts.dismiss()
                store.openWarehouse()
            },
            Screen(surface: "files", state: "triggers", shots: Shot.light([.mac])) { store in
                let thread = try Self.newsletter(in: store)
                let template = try XCTUnwrap(store.add("Weekly review", todo: true, under: thread.id))
                store.add("Clear the inbox", todo: true, under: template.id)
                store.keepAsTemplate(template.id)
                let made = store.now.addingTimeInterval(-8 * 86_400)
                var trigger = Trigger(
                    name: "Monday review", template: "Weekly review", into: nil, intoName: "Everything",
                    rule: .init(every: .week, hour: 9, weekday: 2), created: made)
                trigger = trigger.fired(made.addingTimeInterval(86_400), device: "mac", deviceName: "Mac")
                store.save(trigger)
                store.toasts.dismiss()
                store.openTriggers()
            },
            Screen(surface: "files", state: "trash", shots: Shot.light([.mac])) { store in
                let roadmap = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Q4 roadmap" })
                store.trash(roadmap.id)
                store.toasts.dismiss()
                store.openTrash()
            },
            Screen(surface: "files", state: "archive", shots: Shot.light([.mac])) { store in
                let roadmap = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Q4 roadmap" })
                store.close(roadmap.id, cascade: true)
                store.toasts.dismiss()
                store.openArchive()
            },
            Screen(surface: "modal", state: "capture", shots: Shot.both([.mac]) + Shot.light([.phone])) { store in
                store.modal = .capture
            },
            Screen(surface: "modal", state: "add", shots: Shot.light([.mac, .phone])) { store in
                store.modal = .add(parent: try Self.newsletter(in: store).id)
            },
            Screen(surface: "modal", state: "settings", shots: Shot.both([.mac, .phone])) { store in
                store.modal = .settings
            },
            Screen(surface: "modal", state: "palette", shots: Shot.both([.mac])) { store in
                store.searching = true
            },
            Screen(surface: "modal", state: "close-branch", shots: Shot.both([.mac]) + Shot.light([.phone])) { store in
                store.modal = .closeBranch(id: try Self.newsletter(in: store).id)
            },
            Screen(surface: "modal", state: "delete-forever", shots: Shot.light([.mac])) { store in
                let roadmap = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Q4 roadmap" })
                store.trash(roadmap.id)
                store.toasts.dismiss()
                store.openTrash()
                store.modal = .deleteForever(id: roadmap.id)
            },
            Screen(surface: "modal", state: "fresh-start", shots: Shot.light([.mac])) { store in
                store.modal = .freshStart
            },
            Screen(surface: "modal", state: "shortcuts", shots: Shot.both([.mac])) { store in
                store.modal = .shortcuts
            },
        ]
    }

    /// Every shot on its own: one that cannot be set up or rendered fails naming the screen and
    /// the rest still run, so one run reports every broken screen.
    func testEveryScreenMatchesItsReference() throws {
        let out = try pictureFolder("catalog")
        for screen in catalog {
            for shot in screen.shots {
                let name = "\(screen.surface).\(screen.state)-\(shot.name)"
                do {
                    let store = stillStore()
                    store.sidebar = SidebarVisibility(followsWindow: shot.window.followsWindow)
                    try screen.prepare(store)
                    let image = try render(store: store, in: shot.window, scheme: shot.scheme)
                    try check(image, surface: screen.surface, name: "\(screen.state)-\(shot.name)", into: out)
                } catch {
                    XCTFail("\(name) could not be taken: \(error)")
                    continue
                }
            }
        }
    }

    /// The phone palette is a sheet, which a still picture cannot show over the window: its
    /// content on its own, at the phone's width.
    func testThePhonePaletteMatchesItsReference() throws {
        let out = try pictureFolder("catalog")
        let store = stillStore()
        store.sidebar = SidebarVisibility(followsWindow: true)
        for scheme in [ColorScheme.light, .dark] {
            let sheet = CommandPalette(store: store, inSheet: true) { store.searching = false }
                .frame(width: Window.phone.size.width, height: Window.phone.size.height / 2)
                .background(Theme.raised)
                .environment(\.compact, true)
            let image = try stillImage(sheet, scheme: scheme, scale: 1)
            try check(image, surface: "modal", name: "palette-phone-\(scheme == .dark ? "dark" : "light")", into: out)
        }
    }

    // MARK: Comparing

    /// One picture against its reference. A mismatch, or a reference that had to be recorded,
    /// fails the test naming the screen, and leaves what a person needs to look at in `out`:
    /// the picture as taken, and on a mismatch the reference and the difference between them.
    private func check(_ image: NSImage, surface: String, name: String, into out: URL) throws {
        let reference = Self.references.appendingPathComponent("\(surface).\(name).png")
        // Read before the library runs: in its record modes it overwrites the reference.
        let old = NSImage(contentsOf: reference)
        guard let failure = verifySnapshot(
            of: image, as: strategy, named: name, snapshotDirectory: Self.references.path, testName: surface)
        else { return }
        try png(image).write(to: out.appendingPathComponent("\(surface).\(name).png"))
        if let old {
            try png(old).write(to: out.appendingPathComponent("\(surface).\(name).reference.png"))
            try png(difference(old, image)).write(to: out.appendingPathComponent("\(surface).\(name).diff.png"))
            XCTFail("\(surface).\(name) does not match its reference; see catalog/\(surface).\(name).diff.png. \(failure)")
        } else {
            XCTFail("\(surface).\(name) had no reference; recorded one. \(failure)")
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

    private static func newsletter(in store: BudStore) throws -> Bud {
        try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
    }

    private func render(store: BudStore, in window: Window, scheme: ColorScheme) throws -> NSImage {
        let view = BudRootView(store: store)
            .frame(width: window.size.width, height: window.size.height)
            .environment(\.compact, window.compact)
        return try stillImage(view, scheme: scheme, scale: 1)
    }
}
#endif
