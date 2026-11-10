import XCTest
@testable import BudKit

final class PagePanelsTests: XCTestCase {
    func testTheDefaultLayoutPutsFilesOnTheLeftAndThePagesPanelsOnTheRight() {
        let layout = PanelLayout.standard
        XCTAssertEqual(layout.left, [.files])
        XCTAssertEqual(layout.right, [.properties, .inside, .whereItLives, .linkedFrom, .source])
        XCTAssertEqual(Set(layout.left + layout.right), Set(PagePanel.allCases), "Every panel has a side")
        XCTAssertEqual(layout.side(of: .files), .left)
        XCTAssertEqual(layout.side(of: .source), .right)
        XCTAssertNil(PanelLayout(left: [.files], right: []).side(of: .inside))
    }

    func testOnlySourceStartsCollapsedAndTheChevronFoldsEachPanel() {
        var state = PanelState()
        XCTAssertEqual(state.collapsed, [.source])
        XCTAssertTrue(state.isCollapsed(.source))
        XCTAssertFalse(state.isCollapsed(.inside))
        state.toggle(.inside)
        XCTAssertTrue(state.isCollapsed(.inside))
        state.toggle(.source)
        XCTAssertFalse(state.isCollapsed(.source))
        state.toggle(.inside)
        XCTAssertFalse(state.isCollapsed(.inside))
    }

    func testEachSidebarHidesAndComesBackOnItsOwn() {
        var state = PanelState()
        XCTAssertTrue(state.shows(.left))
        XCTAssertTrue(state.shows(.right))
        state.toggle(.right)
        XCTAssertTrue(state.shows(.left))
        XCTAssertFalse(state.shows(.right))
        state.toggle(.left)
        XCTAssertFalse(state.shows(.left))
        state.toggle(.right)
        XCTAssertTrue(state.shows(.right))
        XCTAssertFalse(state.shows(.left))
    }

    func testThePanelTitlesReadAsTheDesignWritesThem() {
        XCTAssertEqual(PagePanel.allCases.map(\.title), ["Files", "Properties", "Inside", "Where it lives", "Linked from", "Source"])
    }

    func testARowsMetaIsWhatItHoldsThenItsDay() throws {
        var t = Tree.seed()
        let newsletter = try XCTUnwrap(t.children(of: rootID).first { $0.text == "Launch the newsletter" })
        let kids = t.children(of: newsletter.id).count
        XCTAssertEqual(PanelRowText.meta(for: newsletter, in: t), "\(kids) inside")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_GB")
        let day = Date(timeIntervalSince1970: 1_793_750_400)
        let leaf = t.add("Book the printer", todo: true, under: newsletter.id)
        t.setDue(leaf.id, day)
        XCTAssertEqual(PanelRowText.meta(for: t.bud(leaf.id)!, in: t, calendar: calendar), "Due 4 Nov")
        t.setDue(leaf.id, nil)
        t.setWhen(leaf.id, day)
        XCTAssertEqual(PanelRowText.meta(for: t.bud(leaf.id)!, in: t, calendar: calendar), "4 Nov")
        t.setWhen(leaf.id, nil)
        XCTAssertEqual(PanelRowText.meta(for: t.bud(leaf.id)!, in: t, calendar: calendar), "")
    }

    func testTheSourceIsTheFileTheVaultWritesKeysInItsOrder() {
        let made = Date(timeIntervalSince1970: 1_793_700_000)
        let bud = Bud(
            text: "Verify the address", state: .done, body: "Ask the host first.\n\nThen wait a day.",
            when: Date(timeIntervalSince1970: 1_793_750_400), due: Date(timeIntervalSince1970: 1_794_000_000), pinned: true,
            created: made, source: "iphone", from: "linear:PRJ-77", fromState: "moved 2026-11-05T21:00:00Z", tags: ["home", "a: b"])
        XCTAssertEqual(
            MarkdownSource.text(of: bud),
            """
            ---
            state: done
            when: 2026-11-04
            due: 2026-11-06
            pinned: true
            created: 2026-11-03T10:00:00Z
            source: iphone
            from: linear:PRJ-77
            from-state: moved 2026-11-05T21:00:00Z
            tags: [home, "a: b"]
            ---
            Ask the host first.

            Then wait a day.
            """)
    }

    func testANoteWithNothingSetIsItsCreatedLineAndItsBody() {
        let bud = Bud(text: "Warm, not corporate", body: "Say it plainly.", created: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(MarkdownSource.text(of: bud), "---\ncreated: 1970-01-01T00:00:00Z\n---\nSay it plainly.")
    }

    func testAScalarIsQuotedOnlyWhenYAMLWouldReadItDifferently() {
        XCTAssertEqual(MarkdownSource.scalar("mail:M1234"), "mail:M1234")
        XCTAssertEqual(MarkdownSource.scalar("moved 2026-11-05T21:00:00Z"), "moved 2026-11-05T21:00:00Z")
        XCTAssertEqual(MarkdownSource.scalar("#home"), "\"#home\"")
        XCTAssertEqual(MarkdownSource.scalar("say \"hi\": now"), "\"say \\\"hi\\\": now\"")
        XCTAssertEqual(MarkdownSource.scalar("true"), "\"true\"")
        XCTAssertEqual(MarkdownSource.scalar("77"), "\"77\"")
    }
}

#if canImport(SwiftUI)
/// The panels edit through the store, so what they change reaches the vault like any other edit.
@MainActor
final class PagePanelsStoreTests: XCTestCase {
    private func loaded() async -> (BudStore, MemoryVault) {
        let vault = MemoryVault(tree: Tree.seed())
        let store = BudStore(vault: vault)
        await store.reload()
        return (store, vault)
    }

    func testAChildAddedFromInsideLandsUnderTheBudAsItsParentsKind() async throws {
        let (store, vault) = await loaded()
        let note = try XCTUnwrap(store.tree.walk(under: rootID).first { !$0.isTodo && store.tree.hasChildren($0.id) })
        let todo = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.isTodo })
        let before = store.tree.children(of: note.id).map(\.id)
        let planted = try XCTUnwrap(store.add("One more line", todo: store.tree.suggestsTodo(under: note.id), under: note.id))
        let step = try XCTUnwrap(store.add("One more step", todo: store.tree.suggestsTodo(under: todo.id), under: todo.id))
        await store.settle()
        XCTAssertEqual(store.tree.children(of: note.id).map(\.id), before + [planted.id], "At the end of what is inside")
        XCTAssertFalse(planted.isTodo)
        XCTAssertTrue(step.isTodo)
        let records = try await vault.snapshot()
        XCTAssertEqual(records.first { $0.path == planted.id.uuidString }?.parent, note.id.uuidString)
        XCTAssertEqual(records.first { $0.path == step.id.uuidString }?.kind, .todo)
        XCTAssertNil(store.add("   ", todo: false, under: note.id), "An empty line plants nothing")
    }

    func testThePropertyRowsEditThroughTheStore() async throws {
        let (store, vault) = await loaded()
        let todo = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.isTodo && !store.tree.hasChildren($0.id) })
        let note = try XCTUnwrap(store.tree.walk(under: rootID).first { !$0.isTodo })
        let day = Date(timeIntervalSince1970: 1_793_750_400)
        store.setWhen(todo.id, day)
        store.setDue(todo.id, day.addingTimeInterval(86_400))
        store.setPinned(todo.id, true)
        store.tick(todo.id)
        store.update(note.id, text: note.text, todo: true)
        await store.settle()
        let records = try await vault.snapshot()
        let record = try XCTUnwrap(records.first { $0.path == todo.id.uuidString })
        XCTAssertEqual(record.when, day)
        XCTAssertEqual(record.due, day.addingTimeInterval(86_400))
        XCTAssertTrue(record.pinned)
        XCTAssertEqual(record.state, .done)
        XCTAssertEqual(records.first { $0.path == note.id.uuidString }?.kind, .todo)
        store.tick(todo.id)
        store.setWhen(todo.id, nil)
        await store.settle()
        XCTAssertEqual(store.tree.bud(todo.id)?.state, .open)
        XCTAssertNil(store.tree.bud(todo.id)?.when)
    }

    func testThePanelsStartInTheDefaultLayoutAndTheBarHidesASidebar() async {
        let (store, _) = await loaded()
        XCTAssertEqual(store.panels.layout, .standard)
        XCTAssertEqual(store.panels.collapsed, [.source])
        store.panels.toggle(.right)
        XCTAssertFalse(store.panels.shows(.right))
        XCTAssertTrue(store.panels.shows(.left))
    }
}
#endif
