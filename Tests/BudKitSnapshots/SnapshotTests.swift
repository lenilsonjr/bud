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

    func testRendersTheLinkLayer() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        let newsletter = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        let ring = store.tree.children(of: newsletter.id)
        XCTAssertGreaterThanOrEqual(ring.count, 3)
        let lit = ring[0], near = ring[1], third = ring[2]
        let far = try XCTUnwrap(store.tree.buds.first { !store.tree.ancestors(of: $0.id).contains(newsletter.id) && $0.id != newsletter.id && $0.parent != rootID })
        store.setBody(lit.id, "Settle [[\(near.text)]] first, then see [[\(far.text)]].")
        store.setBody(third.id, "Waits on [[\(lit.text)]].")
        store.setBody(far.id, "Read with [[\(lit.text)]].")
        store.center = newsletter.id
        for (name, shown) in [("lit", Optional(lit.id)), ("unlit", nil)] {
            for scheme in [ColorScheme.light, .dark] {
                let view = BudRootView(store: store).frame(width: size.width, height: size.height).environment(\.stillLit, shown)
                let data = try render(view, scheme: scheme)
                let file = folder.appendingPathComponent("canvas-links-\(name)-\(scheme == .dark ? "dark" : "light").png")
                try data.write(to: file)
                XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
            }
        }
    }

    func testRendersTheCanvasUnderALens() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        // Two ticked rows: open to-dos that carry #home. The chips follow the breadcrumb.
        for bud in store.tree.walk(under: rootID).filter({ $0.state == .open }).prefix(3) { store.addTag(bud.id, "home") }
        store.canvasFacets = [.openTodos, .tag("home")]
        XCTAssertEqual(store.canvasLens, LensQuery.todos.and(LensQuery(tags: ["home"])))
        for scheme in [ColorScheme.light, .dark] {
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("canvas-lens-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
        for scheme in [ColorScheme.light, .dark] {
            let view = LensMenu(store: store)
                .padding(24)
                .background(Theme.raised)
            let data = try render(view, scheme: scheme)
            let file = folder.appendingPathComponent("lens-menu-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 2_000, "\(file.lastPathComponent) looks empty")
        }
        // The most linked bud, picked under "Linked to…": its row joins the menu under Links.
        let threads = store.tree.children(of: rootID)
        for from in threads.dropFirst().prefix(2) { store.setBody(from.id, "See [[\(threads[0].text)]]") }
        let linked = try XCTUnwrap(store.links.into.max { $0.value.count < $1.value.count }?.key)
        store.canvasFacets = [.linked(linked, title: store.tree.title(of: linked))]
        let menu = LensMenu(store: store).padding(24).background(Theme.raised)
        try render(menu, scheme: .light).write(to: folder.appendingPathComponent("lens-linked-light.png"))
        try render(store: store, scheme: .light).write(to: folder.appendingPathComponent("canvas-lens-linked-light.png"))
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

    func testRendersTheWarehouse() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first)
        let template = try XCTUnwrap(store.add("Weekly review", todo: true, under: thread.id))
        for step in ["Clear the inbox", "Look at next week", "Pick three things"] {
            store.add(step, todo: true, under: template.id)
        }
        store.keepAsTemplate(template.id)
        store.openWarehouse()
        for scheme in [ColorScheme.light, .dark] {
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("warehouse-\(scheme == .dark ? "dark" : "light").png")
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

    func testRendersPlantedBuds() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        let now = Date()
        let mail = SourceAccount(id: "mail", kind: .mail)
        let calendar = SourceAccount(id: "calendar", kind: .calendar)
        let linear = SourceAccount(id: "linear", kind: .linear)
        let thread = store.add("Move flats", todo: false, under: rootID)!
        let live = store.plant(SourceItem(id: "PRJ-77", title: "Sign the lease", todo: true), from: linear, at: .under(thread.id))
        let moved = store.plant(SourceItem(id: "E-1", title: "Flight to Lisbon"), from: calendar, at: .under(thread.id))
        let cancelled = store.plant(SourceItem(id: "E-2", title: "Flat viewing"), from: calendar, at: .under(thread.id))
        let gone = store.plant(SourceItem(id: "M-9", title: "Deposit receipt"), from: mail, at: .under(thread.id))
        store.setDue(live.id, Date(timeIntervalSince1970: 1_793_750_400))
        store.setWhen(moved.id, Date(timeIntervalSince1970: 1_794_000_000))
        store.marks = [
            "linear:PRJ-77": SourceMark(synced: now.addingTimeInterval(-300), device: "Mac", url: URL(string: "https://example.org/PRJ-77")),
            "calendar:E-1": SourceMark(status: .changed("moved"), at: now.addingTimeInterval(-3600)),
            "calendar:E-2": SourceMark(status: .cancelled),
            "mail:M-9": SourceMark(status: .gone),
        ]
        _ = (cancelled, gone)
        store.center = thread.id
        for scheme in [ColorScheme.light, .dark] {
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("planted-cards-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
        store.openAsFile(live.id)
        for scheme in [ColorScheme.light, .dark] {
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("planted-page-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersTheLinkedFromSection() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        let all = store.tree.walk(under: rootID)
        let target = try XCTUnwrap(all.first { $0.text == "Short names read better in the inbox" })
        let others = all.filter { $0.id != target.id && $0.body.isEmpty }.prefix(2)
        XCTAssertEqual(others.count, 2)
        for (bud, sentence) in zip(others, [
            "Keep it brief. Remember [[Short names read better in the inbox]] when naming the next one. Then ship.",
            "- As [[short names read better in the inbox|the inbox note]] says, a title is a promise",
        ]) {
            store.setBody(bud.id, sentence)
        }
        store.setBody(target.id, target.body + "\n\n- Settle it in [[Pick a name]] first\n- Go through the [[Lease checklist]] before signing")
        store.openAsFile(target.id)
        for scheme in [ColorScheme.light, .dark] {
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("linked-from-\(scheme == .dark ? "dark" : "light").png")
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

    func testRendersTheSoil() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        store.sources = SourceAccount.samples()
        for (name, folded) in [("open", false), ("folded", true)] {
            store.soilFolded = folded
            for scheme in [ColorScheme.light, .dark] {
                let data = try render(store: store, scheme: scheme)
                let file = folder.appendingPathComponent("soil-\(name)-\(scheme == .dark ? "dark" : "light").png")
                try data.write(to: file)
                XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
            }
        }
        // Nine items: three show, then "6 more below".
        let nine = (1...9).map { SourceItem(id: "M-\($0)", title: "Message \($0)", detail: "Sender \($0)", date: Date().addingTimeInterval(Double(-$0 * 60))) }
        store.sources = [SourceAccount(id: "nine", kind: .mail, name: "Mail", items: nine)]
        store.soilFolded = false
        let data = try render(store: store, scheme: .light)
        try data.write(to: folder.appendingPathComponent("soil-nine-light.png"))
        store.soilFolded = false
    }

    func testRendersThePhoneSoilSheet() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        store.sources = SourceAccount.samples()
        for scheme in [ColorScheme.light, .dark] {
            let view = PhoneSoilSheet(store: store).frame(width: 390, height: 420)
            let data = try render(view, scheme: scheme)
            let file = folder.appendingPathComponent("soil-phone-\(scheme == .dark ? "dark" : "light").png")
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

    func testRendersSettingsWithDevices() async throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let missed = MemoryPeers.fixtures()[3].id
        for (name, missing) in [("settings-devices", Set<String>()), ("settings-missed", [missed])] {
            let peers = MemoryPeers(missing: missing)
            let devices = DeviceStore(peers: peers)
            await devices.start()
            if !missing.isEmpty { await devices.remove(MemoryPeers.fixtures()[4].id, rotate: true) }
            let store = BudStore(fileURL: nil, devices: devices)
            for scheme in [ColorScheme.light, .dark] {
                store.modal = .settings
                let data = try render(store: store, scheme: scheme)
                let file = folder.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png")
                try data.write(to: file)
                XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
            }
        }
    }

    func testRendersTheSyncIndicator() async throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let alone = [Device(id: "a91cp4x8d2n6w0j3h5v9b1m7r2ks7t0e", isThisDevice: true, reach: .local)]
        let states: [(String, MemoryPeers, Int, Bool)] = [
            ("sync-connected", MemoryPeers(), 0, false),
            ("sync-pending", MemoryPeers(), 3, false),
            ("sync-apart", MemoryPeers(devices: alone), 3, false),
            ("sync-syncing", MemoryPeers(), 0, true),
        ]
        for (name, peers, pending, syncing) in states {
            await peers.setPendingChanges(pending)
            await peers.setSyncing(syncing)
            let devices = DeviceStore(peers: peers)
            await devices.refresh()
            let store = BudStore(fileURL: nil, devices: devices)
            for scheme in [ColorScheme.light, .dark] {
                let bar = TopBar(store: store, onAdd: {}, onSearch: {}).frame(width: size.width)
                let data = try render(bar, scheme: scheme)
                let file = folder.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png")
                try data.write(to: file)
                XCTAssertGreaterThan(data.count, 5_000, "\(file.lastPathComponent) looks empty")
            }
        }
    }

    func testRendersTheTicketSheet() async throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let made = Date(timeIntervalSince1970: 1_800_000_000)
        let peers = MemoryPeers(now: { made })
        let ticket = try await peers.ticket(withAddresses: false)
        let states: [(String, TicketSheetState)] = [
            ("ticket-fresh", TicketSheetState(ticket: ticket, now: made.addingTimeInterval(2), redeemedBy: nil)),
            ("ticket-expired", TicketSheetState(ticket: ticket, now: made.addingTimeInterval(601), redeemedBy: nil)),
            ("ticket-joined", TicketSheetState(ticket: ticket, now: made.addingTimeInterval(30), redeemedBy: MemoryPeers.fixtures()[1].id)),
        ]
        for (name, state) in states {
            for scheme in [ColorScheme.light, .dark] {
                let sheet = TicketSheetBody(ticket: ticket, state: state, onCopy: {}, onRefresh: {}, onDone: {})
                    .modalCard()
                    .frame(width: ModalMetrics.width)
                    .padding(32)
                    .background(Theme.canvas)
                let data = try render(sheet, scheme: scheme)
                let file = folder.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png")
                try data.write(to: file)
                XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
            }
        }
    }

    func testRendersTheDeviceDialogs() async throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fixtures = MemoryPeers.fixtures()
        let devices = DeviceStore(peers: MemoryPeers())
        await devices.refresh()
        let remove = RemoveDeviceDialog(devices: devices, id: fixtures[4].id, close: {}, present: { _ in })
        let midway = RotationProgress(total: 2, done: 1, reports: [fixtures[1].id: true])
        let rotate = RotateKeyBody(
            lines: DevicesText.rotationLines(Array(fixtures[0...2]), progress: midway, kind: .mac),
            count: DevicesText.rotationCount(midway))
        let fresh = FreshStartDialog(close: {}, perform: { _ in })
        let dialogs: [(String, AnyView)] = [
            ("remove-device", AnyView(remove)), ("rotate-key", AnyView(rotate)), ("fresh-start", AnyView(fresh)),
        ]
        for (name, dialog) in dialogs {
            for scheme in [ColorScheme.light, .dark] {
                let card = dialog
                    .modalCard()
                    .frame(width: ModalMetrics.width)
                    .padding(32)
                    .background(Theme.canvas)
                let data = try render(card, scheme: scheme)
                let file = folder.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png")
                try data.write(to: file)
                XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
            }
        }
    }

    func testRendersTheJoinSheet() async throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let peers = MemoryPeers()
        let ticket = try await peers.ticket(withAddresses: false)
        let full = PeerText.grouped(ticket.text)
        let partial = String(full.prefix(44))
        let source = MemoryPeers.fixtures()[0]
        let states: [(String, JoinPhase, String, Bool)] = [
            ("join-typing", .idle, partial, false),
            ("join-ready", .idle, full, false),
            ("join-failed", .failed(.usedOrExpired), full, false),
            ("join-joined", .joined(source, received: 214, total: 1380), full, false),
            ("join-phone-denied", .idle, "", true),
            ("join-phone-typing", .idle, partial, true),
            ("join-phone-failed", .failed(.usedOrExpired), full, true),
            ("join-phone-joined", .joined(source, received: 214, total: nil), full, true),
        ]
        for (name, phase, text, phone) in states {
            for scheme in [ColorScheme.light, .dark] {
                let body = JoinSheetBody(
                    phase: phase, text: .constant(text), scanning: false, canScan: phone, cameraDenied: phone,
                    onPaste: {}, onJoin: {}, onTypeInstead: {}, onScanAgain: {}, onEdit: {}, onClose: {})
                let sheet = body
                    .modalCard()
                    .frame(width: phone ? 393 - 2 * ModalMetrics.margin : ModalMetrics.width)
                    .padding(phone ? 16 : 32)
                    .background(Theme.canvas)
                    .environment(\.compact, phone)
                let data = try render(sheet, scheme: scheme)
                let file = folder.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png")
                try data.write(to: file)
                XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
            }
        }
    }

    func testRendersTheNearbySheet() async throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let words = ["amber", "cedar", "harbor", "lantern", "otter", "quartz"]
        let tv = Device(id: "t6vbr9e5w1q7y3u8i2o6p0a4s1dh2kxe", reach: .local, name: "Den", kind: .tv)
        let states: [(String, RequestPhase, Bool)] = [
            ("nearby-denied", .idle, true),
            ("nearby-words", .words(words, code: "budr1"), false),
            ("nearby-waiting", .confirming, false),
            ("nearby-added", .confirmed(tv), false),
            ("nearby-refused", .failed(.refused), false),
        ]
        for (name, phase, denied) in states {
            for scheme in [ColorScheme.light, .dark] {
                let sheet = NearbySheetBody(phase: phase, cameraDenied: denied, onAdd: {}, onScanAgain: {}, onClose: {})
                    .modalCard()
                    .frame(width: 393 - 2 * ModalMetrics.margin)
                    .padding(16)
                    .background(Theme.canvas)
                    .environment(\.compact, true)
                let data = try render(sheet, scheme: scheme)
                let file = folder.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png")
                try data.write(to: file)
                XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
            }
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

    func testRendersTheLinkPicker() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let tree = Tree.seed()
        let here = try XCTUnwrap(tree.buds.first { $0.text == "Pick a name" })
        let picker = try XCTUnwrap(LinkPicker(typing: "Keep it under [[s"))
        let rows = picker.candidates(in: tree, excluding: here.id, limit: 3).map { LinkPickerList.Row.bud($0) } + [.plant("s")]
        for scheme in [ColorScheme.light, .dark] {
            let view = LinkPickerList(rows: rows, pick: 0, tree: tree, here: here.text) { _ in }
                .padding(24)
                .frame(width: 480)
                .background(Theme.canvas)
            let data = try render(view, scheme: scheme)
            let file = folder.appendingPathComponent("link-picker-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 2_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersTagsOnAPageAndTheTagPicker() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        let all = store.tree.walk(under: rootID)
        let target = try XCTUnwrap(all.first { $0.text == "Short names read better in the inbox" })
        store.addTag(target.id, "home")
        store.addTag(target.id, "lisbon")
        store.setBody(target.id, target.body + "\n\nAsk about noise on the street #neighbourhood")
        for other in all.filter({ $0.id != target.id }).prefix(4) { store.addTag(other.id, "finance") }
        store.openAsFile(target.id)
        for scheme in [ColorScheme.light, .dark] {
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("tags-on-a-page-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
        XCTAssertEqual(store.tree.bud(target.id)?.tagChips.map(\.inText), [false, false, true])
        let counts = [TagCount(tag: "finance", buds: 4), TagCount(tag: "finland-trip", buds: 1)]
        for scheme in [ColorScheme.light, .dark] {
            let view = TagPicker(carried: ["home"], counts: counts, query: "fin") { _ in }
                .padding(24)
                .background(Theme.canvas)
            let data = try render(view, scheme: scheme)
            let file = folder.appendingPathComponent("tag-picker-\(scheme == .dark ? "dark" : "light").png")
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

    func testRendersTheTrash() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        let roadmap = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Q4 roadmap" })
        store.trash(roadmap.id)
        store.toasts.dismiss()
        store.openTrash()
        for scheme in [ColorScheme.light, .dark] {
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("trash-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersTheArchive() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        let roadmap = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Q4 roadmap" })
        store.close(roadmap.id, cascade: true)
        store.toasts.dismiss()
        store.openArchive()
        for scheme in [ColorScheme.light, .dark] {
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("archive-\(scheme == .dark ? "dark" : "light").png")
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

    private let phone = CGSize(width: 393, height: 852)

    /// The phone layout: Files split with the navigator on top, the canvas, and the palette.
    func testRendersThePhone() throws {
        guard let dir = ProcessInfo.processInfo.environment["BUD_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("BUD_SNAPSHOT_DIR is not set")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = BudStore(fileURL: nil)
        let newsletter = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        store.openAsFile(newsletter.id)
        for scheme in [ColorScheme.light, .dark] {
            let view = BudRootView(store: store).frame(width: phone.width, height: phone.height).environment(\.compact, true)
            let data = try render(view, scheme: scheme)
            let file = folder.appendingPathComponent("phone-files-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
        store.surface = .canvas
        store.center = rootID
        let canvas = BudRootView(store: store).frame(width: phone.width, height: phone.height).environment(\.compact, true)
        try render(canvas, scheme: .light).write(to: folder.appendingPathComponent("phone-canvas-light.png"))
        // A lens on the phone: its chips take a row under the bar.
        store.canvasFacets = [.openTodos, .pinned]
        let lensed = BudRootView(store: store).frame(width: phone.width, height: phone.height).environment(\.compact, true)
        try render(lensed, scheme: .light).write(to: folder.appendingPathComponent("phone-canvas-lens-light.png"))
        store.canvasFacets = []
        let palette = CommandPalette(store: store, onClose: {})
            .padding(12)
            .frame(width: phone.width)
            .background(Theme.canvas)
            .environment(\.compact, true)
        try render(palette, scheme: .light).write(to: folder.appendingPathComponent("phone-palette-light.png"))
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
