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
        let folder = try pictureFolder()

        let store = stillStore()
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
        let folder = try pictureFolder()
        let store = stillStore()
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
        let folder = try pictureFolder()
        let store = stillStore()
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
        let folder = try pictureFolder()
        let store = stillStore()
        let newsletter = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        store.openAsFile(newsletter.id)
        for scheme in [ColorScheme.light, .dark] {
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("files-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    /// A thread with children opens the same page as a leaf: its body, nothing of its children.
    func testRendersAThreadsBodyOnItsPage() throws {
        let folder = try pictureFolder()
        let store = stillStore()
        let newsletter = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        store.setBody(newsletter.id, store.tree.lede(of: newsletter.id) + "\n\nThe first issue goes out before the spring fair.\n\nKeep each issue short enough to read over coffee.")
        store.openAsFile(newsletter.id)
        for scheme in [ColorScheme.light, .dark] {
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("thread-body-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersTheWarehouse() throws {
        let folder = try pictureFolder()
        let store = stillStore()
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

    func testRendersTheTriggers() throws {
        let folder = try pictureFolder()
        let store = stillStore()
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first)
        let template = try XCTUnwrap(store.add("Weekly review", todo: true, under: thread.id))
        store.add("Clear the inbox", todo: true, under: template.id)
        store.keepAsTemplate(template.id)
        let made = store.now.addingTimeInterval(-8 * 86_400)
        var trigger = Trigger(
            name: "Monday review", template: "Weekly review", into: nil, intoName: "Everything",
            rule: .init(every: .week, hour: 9, weekday: 2), created: made)
        trigger = trigger.fired(made.addingTimeInterval(86_400), device: "mac", deviceName: "Mac")
        store.save(trigger)
        store.openTriggers()
        for scheme in [ColorScheme.light, .dark] {
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("triggers-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersTheDocument() throws {
        let folder = try pictureFolder()
        let store = stillStore()
        let short = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.text == "Short names read better in the inbox" })
        store.setBody(short.id, "# First issue\n\n- one story, **one tip**, one date\n- a link to [the club](https://example.org)")
        store.openAsFile(short.id)
        for scheme in [ColorScheme.light, .dark] {
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("document-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    /// The page between its two sidebars: the file tree on the left; Properties, Inside, Where it
    /// lives, Linked from and Source (folded) on the right, reading and then editing, where both
    /// stay. Then the right sidebar hidden from the page bar and Inside folded.
    func testRendersThePageWithPanels() throws {
        let folder = try pictureFolder()
        let store = stillStore()
        let name = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.text == "Pick a name" })
        let roadmap = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Q4 roadmap" })
        store.setBody(name.id, "## What matters\n\nShort, warm, and easy to say out loud. Nothing with **club** in it.\n\n- Ask two readers\n- Check the domain is free")
        store.setBody(roadmap.id, "Settle [[Pick a name]] before the launch notes.")
        store.addTag(name.id, "brand")
        if let done = store.tree.children(of: name.id).first(where: { $0.isTodo }) { store.toggle(done.id) }
        store.openAsFile(name.id)
        for (mode, editing) in [("reading", false), ("editing", true)] {
            for scheme in [ColorScheme.light, .dark] {
                let view = BudRootView(store: store).frame(width: size.width, height: size.height).environment(\.stillEditing, editing)
                let data = try render(view, scheme: scheme)
                let file = folder.appendingPathComponent("page-panels-\(mode)-\(scheme == .dark ? "dark" : "light").png")
                try data.write(to: file)
                XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
            }
        }
        store.sidebar.toggle(.right, in: size)
        store.panels.toggle(.inside)
        try render(store: store, scheme: .light).write(to: folder.appendingPathComponent("page-panels-right-hidden-light.png"))
        store.sidebar = SidebarVisibility(followsWindow: false)
        store.sidebar.toggle(.left, in: size)
        try render(store: store, scheme: .light).write(to: folder.appendingPathComponent("page-panels-left-hidden-light.png"))
        // The lens page has the left toggle too, so the tree never stays stuck hidden.
        store.open(.today)
        try render(store: store, scheme: .light).write(to: folder.appendingPathComponent("lens-left-hidden-light.png"))
    }

    /// Linked from in hand, lifted under the pointer with its place faded, the drop line under
    /// Files where it would land; then the ⋯ menu of a panel, and the layout arranged with the
    /// file tree on the right and Inside hidden.
    func testRendersAPanelOnTheMoveItsMenuAndAnArrangedLayout() throws {
        let folder = try pictureFolder()
        let store = BudStore(fileURL: nil)
        let name = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.text == "Pick a name" })
        let roadmap = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Q4 roadmap" })
        store.setBody(name.id, "## What matters\n\nShort, warm, and easy to say out loud.\n\n- Ask two readers\n- Check the domain is free")
        store.setBody(roadmap.id, "Settle [[Pick a name]] before the launch notes.")
        store.openAsFile(name.id)
        let drag = PanelDrag(panel: .linkedFrom, point: CGPoint(x: 44, y: 640), drop: PanelDrop(side: .left, gap: 1))
        for scheme in [ColorScheme.light, .dark] {
            let view = BudRootView(store: store).frame(width: size.width, height: size.height).environment(\.stillPanelDrag, drag)
            let data = try render(view, scheme: scheme)
            let file = folder.appendingPathComponent("panel-moving-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
        store.arrange { $0.layout.hide(.source) }
        let menu = PanelMenu(panel: .inside, store: store).padding(24).background(Theme.raised)
        try render(menu, scheme: .light).write(to: folder.appendingPathComponent("panel-menu-light.png"))
        try render(menu, scheme: .dark).write(to: folder.appendingPathComponent("panel-menu-dark.png"))
        store.arrange { state in
            state.layout.move(.files, to: .right, at: 0)
            state.layout.hide(.inside)
        }
        try render(store: store, scheme: .light).write(to: folder.appendingPathComponent("panel-arranged-light.png"))
    }

    /// The Agent panel shown on the right under Properties: the scripted chat, with the person's
    /// bubbles green on the right, the agent's grey on the left, a change with Undo between
    /// them, Read under the last bubble it saw, the agent typing, and the composer with This
    /// page. Then the chip taken off and a message sent, answered by the quiet line.
    func testRendersTheAgentPanel() throws {
        let folder = try pictureFolder()
        let store = BudStore(fileURL: nil)
        let name = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.text == "Pick a name" })
        store.setBody(name.id, "## What matters\n\nShort, warm, and easy to say out loud. Nothing with **club** in it.\n\n- Ask two readers\n- Check the domain is free")
        store.openAsFile(name.id)
        store.arrange { $0.layout.move(.agent, to: .right, at: 1) }
        store.agent = .scripted(on: "Pick a name")
        for scheme in [ColorScheme.light, .dark] {
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("agent-panel-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
        store.agent.includesPage = false
        store.agent.typing = false
        store.agent.send("and a day for the printer?", page: nil)
        try render(store: store, scheme: .light).write(to: folder.appendingPathComponent("agent-panel-sent-light.png"))
        store.agent = AgentConversation()
        store.arrange { $0.layout.move(.agent, to: .left, at: 0) }
        try render(store: store, scheme: .light).write(to: folder.appendingPathComponent("agent-panel-empty-left-light.png"))
    }

    func testRendersPlantedBuds() throws {
        let folder = try pictureFolder()
        let store = stillStore()
        let now = store.now
        let mail = SourceAccount(id: "mail", kind: .mail)
        let calendar = SourceAccount(id: "calendar", kind: .calendar)
        let linear = SourceAccount(id: "linear", kind: .linear)
        let thread = store.add("Move flats", todo: false, under: rootID)!
        let live = store.plant(SourceItem(id: "PRJ-77", title: "Sign the lease", todo: true), from: linear, at: .under(thread.id))
        let moved = store.plant(SourceItem(id: "E-1", title: "Flight to Lisbon"), from: calendar, at: .under(thread.id))
        let cancelled = store.plant(SourceItem(id: "E-2", title: "Flat viewing"), from: calendar, at: .under(thread.id))
        let gone = store.plant(SourceItem(id: "M-9", title: "Deposit receipt"), from: mail, at: .under(thread.id))
        store.setDue(live.id, now.addingTimeInterval(86_400))
        store.setWhen(moved.id, now.addingTimeInterval(3 * 86_400))
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

    func testRendersLinksOnAPage() throws {
        let folder = try pictureFolder()
        let store = stillStore()
        let target = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.text == "Short names read better in the inbox" })
        store.setBody(target.id, target.body + "\n\n- Settle it in [[Pick a name]] first\n- Go through the [[Lease checklist]] before signing\n- Nothing is called [[The spring fair]] yet")
        store.openAsFile(target.id)
        for scheme in [ColorScheme.light, .dark] {
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("page-links-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersTheTodayLens() throws {
        let folder = try pictureFolder()
        let store = stillStore()
        store.open(.today)
        for scheme in [ColorScheme.light, .dark] {
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("lens-today-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersThePalette() throws {
        let folder = try pictureFolder()
        let store = stillStore()
        for scheme in [ColorScheme.light, .dark] {
            let palette = CommandPalette(store: store, onClose: {}).padding(32)
            let data = try render(palette, scheme: scheme)
            let file = folder.appendingPathComponent("palette-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 5_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersTheToastAfterPlanting() throws {
        let folder = try pictureFolder()
        let store = stillStore()
        store.add("Write the welcome note", todo: true, under: rootID)
        for scheme in [ColorScheme.light, .dark] {
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("toast-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersTheSoil() throws {
        let folder = try pictureFolder()
        let store = stillStore()
        store.sources = SourceAccount.samples(now: store.now)
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
        let nine = (1...9).map { SourceItem(id: "M-\($0)", title: "Message \($0)", detail: "Sender \($0)", date: store.now.addingTimeInterval(Double(-$0 * 60))) }
        store.sources = [SourceAccount(id: "nine", kind: .mail, name: "Mail", items: nine)]
        store.soilFolded = false
        let data = try render(store: store, scheme: .light)
        try data.write(to: folder.appendingPathComponent("soil-nine-light.png"))
        store.soilFolded = false
    }

    func testRendersThePhoneSoilSheet() throws {
        let folder = try pictureFolder()
        let store = stillStore()
        store.sources = SourceAccount.samples(now: store.now)
        for scheme in [ColorScheme.light, .dark] {
            let view = PhoneSoilSheet(store: store).frame(width: 390, height: 420)
            let data = try render(view, scheme: scheme)
            let file = folder.appendingPathComponent("soil-phone-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersTheQuickAddSheet() throws {
        let folder = try pictureFolder()
        let store = stillStore()
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
        let folder = try pictureFolder()
        let store = stillStore()
        let newsletter = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        for scheme in [ColorScheme.light, .dark] {
            store.modal = .closeBranch(id: newsletter.id)
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("close-branch-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersTheShortcutSheet() throws {
        let folder = try pictureFolder()
        let store = stillStore()
        for scheme in [ColorScheme.light, .dark] {
            store.modal = nil
            try render(store: store, scheme: scheme).write(to: folder.appendingPathComponent("help-button-\(scheme == .dark ? "dark" : "light").png"))
            store.modal = .shortcuts
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("shortcuts-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersSettings() throws {
        let folder = try pictureFolder()
        let store = stillStore()
        for scheme in [ColorScheme.light, .dark] {
            store.modal = .settings
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("settings-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersSettingsWithDevices() async throws {
        let folder = try pictureFolder()
        let missed = MemoryPeers.fixtures()[3].id
        for (name, missing) in [("settings-devices", Set<String>()), ("settings-missed", [missed])] {
            let peers = MemoryPeers(missing: missing, now: stillClock)
            let devices = DeviceStore(peers: peers, now: stillClock)
            await devices.start()
            if !missing.isEmpty { await devices.remove(MemoryPeers.fixtures()[4].id, rotate: true) }
            let store = stillStore(devices: devices)
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
        let folder = try pictureFolder()
        let alone = [Device(id: "a91cp4x8d2n6w0j3h5v9b1m7r2ks7t0e", isThisDevice: true, reach: .local)]
        let states: [(String, MemoryPeers, Int, Bool)] = [
            ("sync-connected", MemoryPeers(now: stillClock), 0, false),
            ("sync-pending", MemoryPeers(now: stillClock), 3, false),
            ("sync-apart", MemoryPeers(devices: alone, now: stillClock), 3, false),
            ("sync-syncing", MemoryPeers(now: stillClock), 0, true),
        ]
        for (name, peers, pending, syncing) in states {
            await peers.setPendingChanges(pending)
            await peers.setSyncing(syncing)
            let devices = DeviceStore(peers: peers, now: stillClock)
            await devices.refresh()
            let store = stillStore(devices: devices)
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
        let folder = try pictureFolder()
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
        let folder = try pictureFolder()
        let fixtures = MemoryPeers.fixtures()
        let devices = DeviceStore(peers: MemoryPeers(now: stillClock), now: stillClock)
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
        let folder = try pictureFolder()
        let peers = MemoryPeers(now: stillClock)
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
        let folder = try pictureFolder()
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
        let folder = try pictureFolder()
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
        let folder = try pictureFolder()
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
        let folder = try pictureFolder()
        let store = stillStore()
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
        let folder = try pictureFolder()
        let store = stillStore()
        for scheme in [ColorScheme.light, .dark] {
            store.modal = .capture
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("sheet-capture-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersTheInbox() throws {
        let folder = try pictureFolder()
        let store = stillStore()
        store.openInbox()
        for scheme in [ColorScheme.light, .dark] {
            let data = try render(store: store, scheme: scheme)
            let file = folder.appendingPathComponent("inbox-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    func testRendersTheTrash() throws {
        let folder = try pictureFolder()
        let store = stillStore()
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
        let folder = try pictureFolder()
        let store = stillStore()
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
        let folder = try pictureFolder()
        let store = stillStore()
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

    /// The view switch folded: on the phone, and in a Mac window too narrow for four segments
    /// beside the bar's buttons, it folds into one button over the board. The Mac window at its
    /// minimum width is pictured too, so the fold there is seen rather than assumed.
    func testRendersTheViewSwitchFolded() throws {
        let folder = try pictureFolder()
        let store = BudStore(fileURL: nil)
        let newsletter = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        store.center = newsletter.id
        store.surface = .board
        let narrow = BudRootView(store: store).frame(width: phone.width, height: phone.height).environment(\.compact, true)
        try render(narrow, scheme: .light).write(to: folder.appendingPathComponent("phone-board-light.png"))
        let narrowWindow = BudRootView(store: store).frame(width: 860, height: 600)
        try render(narrowWindow, scheme: .light).write(to: folder.appendingPathComponent("mac-narrow-board-light.png"))
        let smallestWindow = BudRootView(store: store).frame(width: 900, height: 600)
        try render(smallestWindow, scheme: .light).write(to: folder.appendingPathComponent("mac-smallest-board-light.png"))
    }

    /// The board of the newsletter thread at the design's size, on a fixed day: Open, the three
    /// tag columns in the order they are met, Done, and Cancelled folded to its stub. One card
    /// carries a picture, put on the store before the drawing; one a when, two a due, one a tag
    /// beyond its column's.
    func testRendersTheBoard() async throws {
        let folder = try pictureFolder()
        let (store, _) = try await boardStore()
        for scheme in [ColorScheme.light, .dark] {
            let view = BudRootView(store: store).frame(width: 1440, height: 900)
            let data = try render(view, scheme: scheme)
            let file = folder.appendingPathComponent("board-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    /// The board with a card in hand over Done: the column lit, "Drop to close it" at its top,
    /// and the card raised over it.
    func testRendersTheBoardWithACardOverDone() async throws {
        let folder = try pictureFolder()
        let (store, proof) = try await boardStore()
        let view = BudRootView(store: store)
            .environment(\.stillBoardDrag, BoardDrag(card: proof, over: .done))
            .frame(width: 1440, height: 900)
        let data = try render(view, scheme: .light)
        let file = folder.appendingPathComponent("board-drop-light.png")
        try data.write(to: file)
        XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
    }

    /// The newsletter thread as a board, on the fixed clock: tag columns, a card with a picture,
    /// one done, one cancelled. Returns the store on it and the "doing" card the pictures lift.
    private func boardStore() async throws -> (BudStore, UUID) {
        let now = stillClock()
        let day: TimeInterval = 86_400
        var tree = Tree.seed(now: now)
        let newsletter = try XCTUnwrap(tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        let kids = tree.children(of: newsletter.id)
        let name = kids[0], sender = kids[1], design = kids[2]
        tree.addTag(name.id, "researching")
        tree.setWhen(name.id, now.addingTimeInterval(2 * day))
        tree.addTag(sender.id, "waiting")
        tree.addTag(sender.id, "lawyer")
        tree.setDue(sender.id, now.addingTimeInterval(4 * day))
        let senderKids = tree.children(of: sender.id)
        tree.addTag(senderKids[0].id, "doing")
        tree.toggle(senderKids[1].id)
        let board = tree.add("Living room board", todo: false, under: design.id)
        tree.setBody(board.id, "The sofa goes by the window.")
        let marta = tree.add("Ask the printer about a proof", todo: true, under: design.id)
        tree.addTag(marta.id, "doing")
        tree.setWhen(marta.id, now)
        let sold = tree.add("Sell the old press", todo: true, under: newsletter.id)
        tree.toggle(sold.id)
        let quote = tree.add("Printer quote", todo: true, under: design.id)
        let cancelled = try XCTUnwrap(tree.buds.firstIndex { $0.id == quote.id })
        tree.buds[cancelled].fromState = "cancelled"
        let vault = MemoryVault(tree: tree)
        let store = BudStore(vault: vault, tree: tree, devices: stillDevices())
        await store.settle()
        // The renderer draws at once and never runs a card's load, so the picture is kept on
        // the store first, decoded as a load would keep it.
        let png = try picture()
        store.keepPicture(try XCTUnwrap(BoardPicture.decode(png)), of: board.id)
        store.center = newsletter.id
        store.surface = .board
        return (store, marta.id)
    }

    /// Add column on the newsletter board, the picker open beside the slot: the search line,
    /// On this board with the three columns checked, Other tags from the rest of the vault, and
    /// New tag column. The renderer cannot draw a popover, so the picker is drawn as a plain
    /// view over the board where the popover would sit. Then the ⋯ menu of a tag column.
    func testRendersTheBoardWithThePickerOpen() async throws {
        let folder = try pictureFolder()
        let now = stillClock()
        var tree = Tree.seed(now: now)
        let newsletter = try XCTUnwrap(tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        let kids = tree.children(of: newsletter.id)
        tree.addTag(kids[0].id, "researching")
        tree.addTag(kids[1].id, "waiting")
        tree.addTag(kids[2].id, "doing")
        tree.addTag(tree.children(of: kids[1].id)[0].id, "doing")
        let roadmap = try XCTUnwrap(tree.children(of: rootID).first { $0.text == "Q4 roadmap" })
        for (i, bud) in ([roadmap] + tree.children(of: roadmap.id)).enumerated() {
            tree.addTag(bud.id, "someday")
            if i < 2 { tree.addTag(bud.id, "blocked") }
            if i < 1 { tree.addTag(bud.id, "this-week") }
        }
        let vault = MemoryVault(tree: tree)
        let devices = DeviceStore(peers: MemoryPeers.forLaunch(arguments: [], now: stillClock), now: stillClock)
        let store = BudStore(vault: vault, tree: tree, devices: devices)
        await store.settle()
        store.center = newsletter.id
        store.surface = .board
        // The slot stands after the three tag columns: the page's 24 pt, four columns of 232
        // and their 12 pt gaps; the picker hangs under it.
        let picker = BoardColumnPicker(store: store, id: newsletter.id, source: store.boardTagSource(of: newsletter.id))
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Theme.line))
            .shadow(color: Theme.shadowStrong.opacity(0.4), radius: 16, y: 10)
        for scheme in [ColorScheme.light, .dark] {
            let view = BudRootView(store: store)
                .frame(width: 1440, height: 900)
                .overlay(alignment: .topLeading) { picker.offset(x: 24 + 4 * 244 - 110, y: 132) }
            let data = try render(view, scheme: scheme)
            let file = folder.appendingPathComponent("board-add-column-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
        let edit = BoardColumnEdit(columns: store.boardColumns(of: newsletter.id)) { _, _ in }
        let menu = BoardColumnMenu(tag: "waiting", edit: edit).padding(24).background(Theme.raised)
        try render(menu, scheme: .light).write(to: folder.appendingPathComponent("board-column-menu-light.png"))
    }


    /// A small picture drawn here, so the fixtures carry no file: two washes of the kit.
    private func picture() throws -> Data {
        let image = NSImage(size: NSSize(width: 240, height: 120), flipped: false) { rect in
            NSColor(Palette.leafSoft.light).setFill()
            rect.fill()
            NSColor(Palette.leaf.light).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 70, dy: 30)).fill()
            return true
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    /// The phone layout: Files split with the navigator on top, the canvas, and the palette.
    func testRendersThePhone() throws {
        let folder = try pictureFolder()
        let store = stillStore()
        let newsletter = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        store.openAsFile(newsletter.id)
        try phonePictures("phone-files", store: store, in: folder)
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

    /// A bud's page on the phone: the words first, then its panels stacked under them, every one
    /// folded; then with Inside unfolded, the state flipped as a tap on its header would, since
    /// a picture has no tap.
    func testRendersThePhonePageWithPanels() throws {
        let folder = try pictureFolder()
        let store = BudStore(fileURL: nil)
        let name = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.text == "Pick a name" })
        store.setBody(name.id, "Short, warm, and easy to say out loud. Nothing with **club** in it.\n\n- Ask two readers")
        store.addTag(name.id, "brand")
        store.openAsFile(name.id)
        try phonePictures("phone-page", store: store, in: folder)
        store.panels.toggle(.inside, compact: true)
        let opened = BudRootView(store: store).frame(width: phone.width, height: phone.height).environment(\.compact, true)
        try render(opened, scheme: .light).write(to: folder.appendingPathComponent("phone-page-inside-light.png"))
    }

    /// The whole phone as the store stands, in light and dark, named `name-light.png` and so on.
    private func phonePictures(_ name: String, store: BudStore, in folder: URL) throws {
        for scheme in [ColorScheme.light, .dark] {
            let view = BudRootView(store: store).frame(width: phone.width, height: phone.height).environment(\.compact, true)
            let data = try render(view, scheme: scheme)
            let file = folder.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    /// A fresh store for a calendar picture: the seed on the still clock with a Monday-first
    /// calendar, on the Calendar surface, with two buds scheduled and due so the grids have bars
    /// across their weeks: one under the newsletter over four rows, one under the roadmap over
    /// two. Each picture builds its own, so what one adds never reaches another.
    @MainActor
    private func calendarStore() throws -> BudStore {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_GB")
        calendar.firstWeekday = 2
        let store = stillStore(devices: DeviceStore(peers: MemoryPeers.forLaunch(arguments: [], now: stillClock), now: stillClock, calendar: calendar))
        let day: TimeInterval = 86_400
        let newsletter = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        let issue = try XCTUnwrap(store.add("Send the first issue", todo: true, under: newsletter.id))
        store.setWhen(issue.id, store.now.addingTimeInterval(3 * day))
        store.setDue(issue.id, store.now.addingTimeInterval(20 * day))
        let onboarding = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.text == "Review the onboarding flow" })
        store.setWhen(onboarding.id, store.now.addingTimeInterval(1 * day))
        store.setDue(onboarding.id, store.now.addingTimeInterval(11 * day))
        store.calendarState = CalendarState()
        store.surface = .calendar
        return store
    }

    /// The Calendar view on its month, 1440 by 900 as the board's frame: the seed on the device
    /// store's fixed clock, two buds given a span, and a Monday-first calendar, so the bars and
    /// items land where the board draws them and the picture is the same on every run. One
    /// thread off, so the column shows an unticked row; and the quarter segment, so its quiet
    /// line is seen.
    func testRendersTheMonthCalendar() throws {
        let folder = try pictureFolder()
        let store = try calendarStore()
        // The switches are kept on this device: back to the defaults whatever the test did.
        defer { store.calendarState = CalendarState() }
        XCTAssertEqual(store.monthGrid.month.title, "November 2026")
        XCTAssertFalse(store.monthGrid.bars.isEmpty, "The seed spans weeks")
        let frame = CGSize(width: 1440, height: 900)
        for scheme in [ColorScheme.light, .dark] {
            let view = BudRootView(store: store).frame(width: frame.width, height: frame.height)
            let data = try render(view, scheme: scheme)
            let file = folder.appendingPathComponent("calendar-month-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
        if let roadmap = store.calendarThreads.first(where: { $0.title == "Q4 roadmap" }) { store.toggleThread(roadmap.id) }
        let hidden = BudRootView(store: store).frame(width: frame.width, height: frame.height)
        try render(hidden, scheme: .light).write(to: folder.appendingPathComponent("calendar-month-thread-off-light.png"))
        store.calendarState = CalendarState(range: .quarter)
        let quarter = BudRootView(store: store).frame(width: frame.width, height: frame.height)
        try render(quarter, scheme: .light).write(to: folder.appendingPathComponent("calendar-quarter-coming-light.png"))
    }

    /// The Calendar view on its day and on its week, 1440 by 900 as the board's frames: the seed
    /// on the fixed clock, Tuesday 3 November at ten, with two spans over the day, a bud due
    /// that day with no time, and buds given hours, two of them overlapping, so the all-day row,
    /// the blocks and the now line all land where the board draws them.
    func testRendersTheDayAndWeekCalendars() throws {
        let folder = try pictureFolder()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_GB")
        calendar.firstWeekday = 2
        let store = stillStore(devices: DeviceStore(peers: MemoryPeers.forLaunch(arguments: [], now: stillClock), now: stillClock, calendar: calendar))
        defer { store.calendarState = CalendarState() }
        func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
        }
        func bud(_ text: String) throws -> Bud { try XCTUnwrap(store.tree.walk(under: rootID).first { $0.text == text }) }
        // The spans: the onboarding review from Monday past the week, the first issue to Friday.
        let onboarding = try bud("Review the onboarding flow")
        store.setWhen(onboarding.id, at(2))
        store.setDue(onboarding.id, at(23))
        let newsletter = try bud("Launch the newsletter")
        let issue = try XCTUnwrap(store.add("Send the first issue", todo: true, under: newsletter.id))
        store.setWhen(issue.id, at(3))
        store.setDue(issue.id, at(6))
        // Due today, with no time: in the all-day row with its flag.
        store.setDue(try bud("Verify the address").id, at(3))
        // The hours: the seed's walk at ten, a review beside it, the name in the afternoon, a
        // lesson in the evening, and the rest of the week's.
        let name = try bud("Pick a name")
        store.setWhen(name.id, at(3, 14, 0))
        store.setDue(name.id, at(3, 14, 30))
        let roadmap = try bud("Q4 roadmap")
        let budget = try XCTUnwrap(store.add("Budget review", todo: true, under: roadmap.id))
        store.setWhen(budget.id, at(3, 10, 15))
        store.setDue(budget.id, at(3, 11, 30))
        let lesson = try bud("Ten minutes a day")
        store.setWhen(lesson.id, at(3, 18, 0))
        store.setDue(lesson.id, at(3, 19, 0))
        let language = try bud("Learn a language")
        let next = try XCTUnwrap(store.add("Lesson 15", todo: true, under: language.id))
        store.setWhen(next.id, at(5, 18, 0))
        store.setDue(next.id, at(5, 19, 0))
        let health = try bud("Health reset")
        let run = try XCTUnwrap(store.add("Long run", todo: true, under: health.id))
        store.setWhen(run.id, at(8, 8, 0))
        store.setDue(run.id, at(8, 9, 30))
        let sync = try XCTUnwrap(store.add("Roadmap sync", todo: true, under: roadmap.id))
        store.setWhen(sync.id, at(4, 14, 0))
        store.setDue(sync.id, at(4, 15, 0))
        let samples = try XCTUnwrap(store.add("Paper samples arrive", todo: true, under: newsletter.id))
        store.setDue(samples.id, at(7, 12, 30))
        store.surface = .calendar
        let frame = CGSize(width: 1440, height: 900)

        store.calendarState = CalendarState(range: .day)
        let day = store.dayPlan
        XCTAssertEqual(day.bars.map(\.label), ["Review the onboarding flow · day 2 of 22, due 23 Nov", "Send the first issue · day 1 of 4, due 6 Nov", "Verify the address"])
        XCTAssertEqual(day.blocks.map(\.time), ["10:00", "10:15–11:30", "14:00–14:30", "18:00–19:00"])
        XCTAssertEqual(day.blocks.prefix(2).map(\.lanes), [2, 2], "The walk and the review overlap, so they share the column")
        XCTAssertEqual(day.now?.minutes, 10 * 60)
        let dayFile = folder.appendingPathComponent("calendar-day-light.png")
        try render(BudRootView(store: store).frame(width: frame.width, height: frame.height), scheme: .light).write(to: dayFile)
        try render(BudRootView(store: store).frame(width: frame.width, height: frame.height), scheme: .dark).write(to: folder.appendingPathComponent("calendar-day-dark.png"))

        store.calendarState = CalendarState(range: .week)
        let week = store.weekPlan
        XCTAssertEqual(week.bars.map(\.label), ["Review the onboarding flow → 23 Nov", "Send the first issue · due 6 Nov", "Verify the address"])
        XCTAssertEqual(week.blocks.count, 8)
        XCTAssertEqual(week.now?.column, 1)
        let weekFile = folder.appendingPathComponent("calendar-week-light.png")
        let data = try render(BudRootView(store: store).frame(width: frame.width, height: frame.height), scheme: .light)
        try data.write(to: weekFile)
        XCTAssertGreaterThan(data.count, 10_000, "\(weekFile.lastPathComponent) looks empty")
        try render(BudRootView(store: store).frame(width: frame.width, height: frame.height), scheme: .dark).write(to: folder.appendingPathComponent("calendar-week-dark.png"))
    }

    /// The Calendar view on its year and on a custom range, 1440 by 900 as the board's frames:
    /// the seed on the still clock with the month picture's two spanning buds, and the newsletter
    /// thread given a due day in February so the picker offers "Until … is due". A popover cannot
    /// open in a still picture, so the picker's content is drawn in its panel over the frame,
    /// under the segments where the board places it.
    func testRendersTheYearAndTheRangePicker() throws {
        let folder = try pictureFolder()
        let store = try calendarStore()
        defer { store.calendarState = CalendarState() }
        let newsletter = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        store.setDue(newsletter.id, store.now.addingTimeInterval(99 * 86_400))
        store.calendarState = CalendarState(range: .year)
        XCTAssertEqual(store.calendarTitle, "2026")
        XCTAssertEqual(store.yearGrid.months.count, 12)
        XCTAssertTrue(store.yearGrid.months[10].days.contains { $0.shade != nil }, "November is shaded by the spans")
        let frame = CGSize(width: 1440, height: 900)
        for scheme in [ColorScheme.light, .dark] {
            let view = BudRootView(store: store).frame(width: frame.width, height: frame.height)
            let data = try render(view, scheme: scheme)
            let file = folder.appendingPathComponent("calendar-year-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
        store.pickRange(CustomRange(first: YearMonth(year: 2026, month: 11), last: YearMonth(year: 2027, month: 2)))
        XCTAssertEqual(store.calendarTitle, "Nov 2026 – Feb 2027")
        XCTAssertEqual(store.yearGrid.months.map(\.title), ["November", "December", "January", "February"])
        XCTAssertEqual(store.rangePresets.map(\.title), ["Next 3 months", "This half", "Until Launch the newsletter is due"])
        let panel = RoundedRectangle(cornerRadius: Radius.toast, style: .continuous)
        let picker = RangePicker(store: store)
            .background(Theme.raised, in: panel)
            .overlay(panel.stroke(Theme.lineStrong, lineWidth: 1))
        for scheme in [ColorScheme.light, .dark] {
            let open = ZStack(alignment: .topTrailing) {
                BudRootView(store: store).frame(width: frame.width, height: frame.height)
                picker.padding(.top, 104).padding(.trailing, 288)
            }
            .frame(width: frame.width, height: frame.height)
            let data = try render(open, scheme: scheme)
            let file = folder.appendingPathComponent("calendar-custom-picker-\(scheme == .dark ? "dark" : "light").png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
    }

    /// The timeline of the month, the quarter and the year, each on the still clock with the
    /// month picture's spanning buds and one more that runs past the month's end, so the month
    /// draws a bar flat at its edge and the quarter draws it whole. Then the month with its
    /// first thread folded to its header.
    func testRendersTheTimelines() throws {
        let folder = try pictureFolder()
        let store = try calendarStore()
        defer { store.calendarState = CalendarState() }
        let day: TimeInterval = 86_400
        let newsletter = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        let minutes = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.text == "Ten minutes a day" })
        store.setWhen(minutes.id, store.now.addingTimeInterval(7 * day))
        store.setDue(minutes.id, store.now.addingTimeInterval(45 * day))
        store.calendarState = CalendarState(range: .month, layout: .timeline)
        let month = try XCTUnwrap(store.timeline)
        XCTAssertEqual(month.threads.map(\.title), ["Launch the newsletter", "Q4 roadmap", "Learn a language", "Health reset"])
        XCTAssertTrue(month.threads[2].rows.contains { $0.endsAfter }, "The language bar runs past the month")
        let frame = CGSize(width: 1440, height: 900)
        for range in [CalendarRange.month, .quarter, .year] {
            store.calendarState.range = range
            XCTAssertNotNil(store.timeline)
            let view = BudRootView(store: store).frame(width: frame.width, height: frame.height)
            let data = try render(view, scheme: .light)
            let file = folder.appendingPathComponent("calendar-timeline-\(range.rawValue.lowercased())-light.png")
            try data.write(to: file)
            XCTAssertGreaterThan(data.count, 10_000, "\(file.lastPathComponent) looks empty")
        }
        store.calendarState.range = .month
        store.toggleCollapsed(newsletter.id)
        XCTAssertTrue(try XCTUnwrap(store.timeline?.threads.first?.isCollapsed))
        let folded = BudRootView(store: store).frame(width: frame.width, height: frame.height)
        try render(folded, scheme: .light).write(to: folder.appendingPathComponent("calendar-timeline-month-folded-light.png"))
        try render(BudRootView(store: store).frame(width: frame.width, height: frame.height), scheme: .dark)
            .write(to: folder.appendingPathComponent("calendar-timeline-month-folded-dark.png"))
    }

    private func render(store: BudStore, scheme: ColorScheme) throws -> Data {
        try render(BudRootView(store: store).frame(width: size.width, height: size.height), scheme: scheme)
    }

    /// One frame at two pixels per point, as PNG data.
    private func render(_ content: some View, scheme: ColorScheme) throws -> Data {
        try png(stillImage(content, scheme: scheme, scale: 2))
    }
}
#endif
