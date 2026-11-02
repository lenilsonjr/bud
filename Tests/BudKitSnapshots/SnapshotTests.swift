import XCTest
@testable import BudKit

#if canImport(SwiftUI) && os(macOS)
import AppKit
import SwiftUI

/// Renders the canvas to PNG files for a person to look at. Runs only when `BUD_SNAPSHOT_DIR`
/// is set, so the gate on Linux and an ordinary `swift test` skip it.
@MainActor
final class SnapshotTests: XCTestCase {
    private let size = CGSize(width: 1400, height: 900)

    func testRendersTheCanvasInBothAppearances() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let store = BudStore(fileURL: nil)
        let newsletter = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        let deep = try XCTUnwrap(store.tree.children(of: newsletter.id).first)
        // One done to-do, so the pictures show the struck title and the filled check.
        if let leaf = store.tree.children(of: deep.id).first(where: { $0.isTodo }) { store.toggle(leaf.id) }

        for (name, center) in [("hub", rootID), ("deep", deep.id)] {
            store.center = center
            for scheme in [ColorScheme.light, .dark] {
                let data = try render(store: store, scheme: scheme)
                let file = folder.appendingPathComponent("canvas-\(name)-\(scheme == .dark ? "dark" : "light").png")
                try data.write(to: file)
                XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
            }
        }
    }

    func testRendersTheFilesView() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        let newsletter = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        store.openAsFile(newsletter.id)
        for scheme in [ColorScheme.light, .dark] {
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("files-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersTheOutline() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        let newsletter = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        let name = try XCTUnwrap(store.tree.children(of: newsletter.id).first { $0.text == "Pick a name" })
        store.openAsFile(newsletter.id)
        for scheme in [ColorScheme.light, .dark] {
            let page = OutlinePage(store: store, expanded: [name.id]).frame(width: size.width - FilesView.sidebarWidth, height: size.height)
            let data = try render(page.background(Theme.canvas), scheme: scheme)
            let file = folder.appendingPathComponent("outline-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersTheDocument() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        let short = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.text == "Short names read better in the inbox" })
        store.setBody(short.id, "# First issue\n\n- one story, **one tip**, one date\n- a link to [the club](https://example.org)")
        store.setDue(short.id, Date(timeIntervalSince1970: 1_793_750_400))
        store.openAsFile(short.id)
        for scheme in [ColorScheme.light, .dark] {
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("document-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersTheTodayLens() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        store.open(.today)
        for scheme in [ColorScheme.light, .dark] {
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("lens-today-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersThePalette() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        for scheme in [ColorScheme.light, .dark] {
            let palette = CommandPalette(store: store, onClose: {}).padding(32)
            let data = try render(palette, scheme: scheme)
            let file = folder.appendingPathComponent("palette-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 5_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersTheToastAfterPlanting() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        store.add("Write the welcome note", todo: true, under: rootID)
        for scheme in [ColorScheme.light, .dark] {
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("toast-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersTheQuickAddSheet() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        let newsletter = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        for scheme in [ColorScheme.light, .dark] {
            store.modal = .add(parent: newsletter.id)
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("sheet-add-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersTheCloseBranchDialog() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        let newsletter = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        for scheme in [ColorScheme.light, .dark] {
            store.modal = .closeBranch(id: newsletter.id)
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("close-branch-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersSettings() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        for scheme in [ColorScheme.light, .dark] {
            store.modal = .settings
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("settings-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersTheFourButtons() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            let row = HStack(spacing: 12) {
                Button { } label: { BudButtonLabel(title: "Add", systemImage: "plus") }.buttonStyle(.budPrimary)
                Button { } label: { BudButtonLabel(title: "Cancel") }.buttonStyle(.budSecondary)
                Button { } label: { BudButtonLabel(title: "Pin") }.buttonStyle(.budGhost)
                Button { } label: { BudButtonLabel(title: "Delete") }.buttonStyle(.budDestructive)
            }
            .padding(24)
            .background(Theme.surface)
            let data = try render(row, scheme: scheme)
            let file = folder.appendingPathComponent("buttons-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 2_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersTheCaptureSheet() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        for scheme in [ColorScheme.light, .dark] {
            store.modal = .capture
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("sheet-capture-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersTheInbox() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        store.openInbox()
        for scheme in [ColorScheme.light, .dark] {
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("inbox-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersTheOpenedCard() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        let newsletter = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        for scheme in [ColorScheme.light, .dark] {
            let card = DetailCard(id: newsletter.id, store: store, onEnrich: {}, onClose: {}).padding(24)
            let data = try render(card, scheme: scheme)
            let file = folder.appendingPathComponent("card-open-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 5_000, "\(file.lastPathComponent) looks empty")
        }
    }

    private func render(store: BudStore, scheme: ColorScheme) throws -> Data {
        try render(BudRootView(store: store).frame(width: size.width, height: size.height), scheme: scheme)
    }

    private func render(_ content: some View, scheme: ColorScheme) throws -> Data {
        let view = content
            .environment(\.colorScheme, scheme)
            .environment(\.stillPicture, true)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let appearance = try XCTUnwrap(NSAppearance(named: scheme == .dark ? .darkAqua : .aqua))
        var image: NSImage?
        appearance.performAsCurrentDrawingAppearance { image = renderer.nsImage }
        let nsImage = try XCTUnwrap(image, "ImageRenderer produced no image")
        let tiff = try XCTUnwrap(nsImage.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}
#endif
