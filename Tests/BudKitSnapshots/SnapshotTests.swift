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

    func testRendersTheQuickAddSheet() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        let newsletter = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        for scheme in [ColorScheme.light, .dark] {
            let sheet = AddSheet(store: store, parent: newsletter.id).frame(width: 420)
            let data = try render(sheet, scheme: scheme)
            let file = folder.appendingPathComponent("sheet-add-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 5_000, "\(file.lastPathComponent) looks empty")
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
        let view = content.environment(\.colorScheme, scheme)
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
