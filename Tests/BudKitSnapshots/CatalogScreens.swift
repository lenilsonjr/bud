import XCTest
@testable import BudKit

#if canImport(SwiftUI)
import SwiftUI

/// The screens of the catalog: each one's surface, state, the windows and appearances it is
/// taken in, and how to put the store into that state. The Mac's catalog and the iOS app's both
/// read this one table, so the two sets of pictures line up name for name and size for size.
enum Catalog {
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

        /// The file name of one shot, without the extension: `surface.state-window-scheme`.
        func name(_ shot: Shot) -> String { "\(surface).\(state)-\(shot.name)" }
    }

    /// The phone palette is a sheet, which a still picture cannot show over the window: its
    /// content on its own, at the phone's width, under these names in the modal surface.
    static let phonePalette: [(scheme: ColorScheme, name: String)] = [ColorScheme.light, .dark].map {
        ($0, "palette-phone-\($0 == .dark ? "dark" : "light")")
    }

    /// The phone palette's size: the phone's width and half its height.
    static let phonePaletteSize = CGSize(width: Window.phone.size.width, height: Window.phone.size.height / 2)

    @MainActor
    static var screens: [Screen] {
        [
            Screen(surface: "canvas", state: "hub", shots: Shot.both([.mac, .phone]) + Shot.light(Window.pads)) { _ in },
            Screen(surface: "canvas", state: "thread", shots: Shot.both([.mac]) + Shot.light([.phone])) { store in
                let thread = try newsletter(in: store)
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
                store.openAsFile(try newsletter(in: store).id)
                store.sidebar.toggle(.left, in: Window.mac.size)
                store.sidebar.toggle(.right, in: Window.mac.size)
            },
            Screen(surface: "files", state: "sidebar-shown", shots: Shot.light([.phone])) { store in
                store.openAsFile(try newsletter(in: store).id)
                store.sidebar.toggle(.left, in: Window.phone.size)
            },
            Screen(surface: "files", state: "today", shots: Shot.both([.mac])) { store in
                store.open(.today)
            },
            Screen(surface: "files", state: "inbox", shots: Shot.light([.mac, .phone])) { store in
                store.openInbox()
            },
            Screen(surface: "files", state: "warehouse", shots: Shot.light([.mac])) { store in
                let thread = try newsletter(in: store)
                let template = try XCTUnwrap(store.add("Weekly review", todo: true, under: thread.id))
                for step in ["Clear the inbox", "Look at next week", "Pick three things"] {
                    store.add(step, todo: true, under: template.id)
                }
                store.keepAsTemplate(template.id)
                store.toasts.dismiss()
                store.openWarehouse()
            },
            Screen(surface: "files", state: "triggers", shots: Shot.light([.mac])) { store in
                let thread = try newsletter(in: store)
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
                store.modal = .add(parent: try newsletter(in: store).id)
            },
            Screen(surface: "modal", state: "settings", shots: Shot.both([.mac, .phone])) { store in
                store.modal = .settings
            },
            Screen(surface: "modal", state: "palette", shots: Shot.both([.mac])) { store in
                store.searching = true
            },
            Screen(surface: "modal", state: "close-branch", shots: Shot.both([.mac]) + Shot.light([.phone])) { store in
                store.modal = .closeBranch(id: try newsletter(in: store).id)
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

    @MainActor
    static func newsletter(in store: BudStore) throws -> Bud {
        try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
    }

    // MARK: The manifest

    /// What became of a screen, as the manifest records it. `planned` is written before any
    /// picture is taken and stays when the run dies before reaching the screen. `taken` is a
    /// picture with no reference to hold it against, which is every picture the iOS app takes.
    enum Outcome: String {
        case planned, matched, mismatched, recorded, taken, failed
    }

    /// One line of `manifest.txt` in `out`: the screen and its outcome, appended, so the last
    /// line for a name is its answer and a run that dies leaves every earlier line in place.
    static func note(_ name: String, _ outcome: Outcome, in out: URL) throws {
        let file = out.appendingPathComponent("manifest.txt")
        let line = Data("\(name) \(outcome.rawValue)\n".utf8)
        guard let handle = try? FileHandle(forWritingTo: file) else { return try line.write(to: file) }
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }
}
#endif
