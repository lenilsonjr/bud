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
        let window = CGSize(width: 1400, height: 900)
        store.sidebar.toggle(.right, in: window)
        XCTAssertFalse(store.sidebar.isShown(.right, in: window))
        XCTAssertTrue(store.sidebar.isShown(.left, in: window))
    }

    func testLinkedFromIsReadOncePerChangeOfTheTree() async throws {
        let (store, _) = await loaded()
        let threads = store.tree.children(of: rootID)
        let target = threads[0], from = threads[1]
        XCTAssertEqual(store.backlinks(to: target.id), [])
        store.setBody(from.id, "Settle [[\(target.text)]] first.")
        await store.settle()
        let rows = store.backlinks(to: target.id)
        XCTAssertEqual(rows.map(\.from), [from.id])
        XCTAssertEqual(rows, store.tree.backlinks(to: target.id))
        store.center = target.id
        XCTAssertEqual(store.backlinks(to: target.id), rows, "The same rows until the tree changes")
        store.setBody(from.id, "Nothing links any more.")
        await store.settle()
        XCTAssertEqual(store.backlinks(to: target.id), [])
    }

    func testTheSourcePanelReadsTheFileThroughTheVault() async throws {
        let (store, _) = await loaded()
        let bud = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.isTodo && $0.due == nil && $0.when == nil && !$0.pinned })
        store.setBody(bud.id, "Ask the host first.")
        store.setPinned(bud.id, true)
        let text = try XCTUnwrap(await store.fileText(of: bud.id))
        XCTAssertEqual(text, "---\nstate: open\npinned: true\n---\nAsk the host first.")
        XCTAssertNil(await store.fileText(of: UUID()))
    }
}
#endif
