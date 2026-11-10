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

    func testADroppedPanelLandsWhereTheLineWasInEitherSidebar() {
        var layout = PanelLayout.standard
        layout.move(.inside, to: .left, at: 0)
        XCTAssertEqual(layout.left, [.inside, .files])
        XCTAssertEqual(layout.right, [.properties, .whereItLives, .linkedFrom, .source])
        layout.move(.files, to: .right, at: 99)
        XCTAssertEqual(layout.left, [.inside])
        XCTAssertEqual(layout.right, [.properties, .whereItLives, .linkedFrom, .source, .files], "Past the end is last")
        layout.move(.source, to: .right, at: 0)
        XCTAssertEqual(layout.right, [.source, .properties, .whereItLives, .linkedFrom, .files], "Within one side it is taken out first")
        layout.move(.source, to: .right, at: -3)
        XCTAssertEqual(layout.right, [.source, .properties, .whereItLives, .linkedFrom, .files])
        XCTAssertEqual(layout.hidden, [])
    }

    func testTheGapUnderThePointerCountsThePanelsOldPlaceAndLinesTheEdgeItLandsOn() {
        let layout = PanelLayout.standard
        let frames: [PagePanel: CGRect] = [
            .properties: CGRect(x: 1100, y: 0, width: 300, height: 200),
            .inside: CGRect(x: 1100, y: 200, width: 300, height: 100),
            .whereItLives: CGRect(x: 1100, y: 300, width: 300, height: 100),
            .linkedFrom: CGRect(x: 1100, y: 400, width: 300, height: 100),
            .source: CGRect(x: 1100, y: 500, width: 300, height: 32),
        ]
        XCTAssertEqual(PanelDrop.under(CGPoint(x: 1200, y: 10), on: .right, frames: frames, layout: layout).gap, 0)
        XCTAssertEqual(PanelDrop.under(CGPoint(x: 1200, y: 150), on: .right, frames: frames, layout: layout).gap, 1, "Past the middle of Properties")
        XCTAssertEqual(PanelDrop.under(CGPoint(x: 1200, y: 360), on: .right, frames: frames, layout: layout).gap, 3)
        XCTAssertEqual(PanelDrop.under(CGPoint(x: 1200, y: 800), on: .right, frames: frames, layout: layout).gap, 5, "Below them all is after the last")
        XCTAssertEqual(PanelDrop.under(CGPoint(x: 100, y: 800), on: .left, frames: frames, layout: layout).gap, 0, "A side with no frames yet puts it first")

        let third = PanelDrop(side: .right, gap: 3)
        XCTAssertEqual(third.line(on: .linkedFrom, in: layout), .above)
        XCTAssertNil(third.line(on: .whereItLives, in: layout))
        XCTAssertEqual(PanelDrop(side: .right, gap: 5).line(on: .source, in: layout), .below)
        XCTAssertNil(PanelDrop(side: .right, gap: 5).line(on: .files, in: layout))
        XCTAssertEqual(third.index(moving: .properties, in: layout), 2, "Moving down: the old place is counted out")
        XCTAssertEqual(third.index(moving: .source, in: layout), 3, "Moving up: as the gap says")
        XCTAssertEqual(third.index(moving: .files, in: layout), 3, "From the other side: as the gap says")
        var moved = layout
        moved.move(.properties, to: .right, at: third.index(moving: .properties, in: layout))
        XCTAssertEqual(moved.right, [.inside, .whereItLives, .properties, .linkedFrom, .source])

        XCTAssertEqual(PanelDrop.side(at: 100, in: 1400, left: 273, right: 301), .left)
        XCTAssertEqual(PanelDrop.side(at: 1200, in: 1400, left: 273, right: 301), .right)
        XCTAssertNil(PanelDrop.side(at: 700, in: 1400, left: 273, right: 301), "Over the page")
        XCTAssertNil(PanelDrop.side(at: 100, in: 1400, left: nil, right: 301), "A hidden sidebar takes nothing")
    }

    func testTheMenuOffersItsItemsInOrderAndDisablesWhatDoesNothing() {
        var state = PanelState()
        let items = PanelMenuItem.allCases
        XCTAssertEqual(
            items.map { $0.title(for: .properties, in: state) },
            ["Move to left sidebar", "Move up", "Move down", "Collapse", "Hide panel", "Show hidden panels", "Reset layout"]
        )
        XCTAssertEqual(items.map(\.startsGroup), [false, false, false, true, false, true, false])
        XCTAssertEqual(PanelMenuItem.moveToOtherSide.title(for: .files, in: state), "Move to right sidebar")
        XCTAssertEqual(PanelMenuItem.collapse.title(for: .source, in: state), "Expand")
        XCTAssertEqual(
            items.map { $0.isEnabled(for: .properties, in: state) },
            [true, false, true, true, true, false, false], "At the top, nothing hidden, the standard layout"
        )
        XCTAssertFalse(PanelMenuItem.moveDown.isEnabled(for: .source, in: state))
        XCTAssertTrue(PanelMenuItem.moveUp.isEnabled(for: .source, in: state))

        PanelMenuItem.moveDown.apply(to: &state, for: .properties)
        XCTAssertEqual(state.layout.right, [.inside, .properties, .whereItLives, .linkedFrom, .source])
        PanelMenuItem.moveUp.apply(to: &state, for: .properties)
        XCTAssertEqual(state.layout.right, PanelLayout.standard.right)
        PanelMenuItem.moveUp.apply(to: &state, for: .properties)
        XCTAssertEqual(state.layout.right, PanelLayout.standard.right, "Nothing above the top")
        PanelMenuItem.moveToOtherSide.apply(to: &state, for: .properties)
        XCTAssertEqual(state.layout.left, [.files, .properties])
        PanelMenuItem.hide.apply(to: &state, for: .source)
        PanelMenuItem.hide.apply(to: &state, for: .inside)
        XCTAssertEqual(state.layout.hidden, [.inside, .source])
        XCTAssertEqual(state.layout.right, [.whereItLives, .linkedFrom])
        XCTAssertTrue(PanelMenuItem.showHidden.isEnabled(for: .files, in: state))
        XCTAssertTrue(PanelMenuItem.reset.isEnabled(for: .files, in: state))
        PanelMenuItem.collapse.apply(to: &state, for: .files)
        XCTAssertTrue(state.isCollapsed(.files))
        PanelMenuItem.showHidden.apply(to: &state, for: .files)
        XCTAssertEqual(state.layout.right, [.whereItLives, .linkedFrom, .inside, .source], "Back at the end of their usual side")
        XCTAssertEqual(state.layout.hidden, [])
    }

    func testALayoutFromANewerBuildReadsWithItsUnknownPanelsSkipped() throws {
        let text = "{\"left\":[\"files\",\"calendar\"],\"right\":[\"inside\",\"agent\",\"properties\"]}"
        let layout = try JSONDecoder().decode(PanelLayout.self, from: Data(text.utf8))
        XCTAssertEqual(layout.left, [.files])
        XCTAssertEqual(layout.right, [.inside, .properties], "The known ones keep their order")
        XCTAssertEqual(layout.hidden, [.whereItLives, .linkedFrom, .source], "On neither side is hidden")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let written = try encoder.encode(layout)
        XCTAssertEqual(String(decoding: written, as: UTF8.self), "{\"left\":[\"files\"],\"right\":[\"inside\",\"properties\"]}")
        XCTAssertEqual(try JSONDecoder().decode(PanelLayout.self, from: written), layout)
    }

    func testTheLastPanelThePageShowsCannotHide() {
        var state = PanelState(layout: PanelLayout(left: [.files], right: []))
        XCTAssertFalse(PanelMenuItem.hide.isEnabled(for: .files, in: state))
        state.layout.move(.inside, to: .left, at: 1)
        XCTAssertTrue(PanelMenuItem.hide.isEnabled(for: .files, in: state))
        XCTAssertFalse(PanelMenuItem.hide.isEnabled(for: .files, in: state, onBudPage: false), "A lens shows the tree alone")
        XCTAssertFalse(PanelMenuItem.hide.isEnabled(for: .files, in: PanelState(), onBudPage: false))
        XCTAssertTrue(PanelMenuItem.hide.isEnabled(for: .files, in: PanelState(), onBudPage: true))
        XCTAssertEqual(PanelLayout.standard.shown(on: .right, onBudPage: false), [])
        XCTAssertEqual(PanelLayout.standard.shown(on: .right, onBudPage: true), PanelLayout.standard.right)
        var arranged = PanelLayout.standard
        arranged.move(.files, to: .right, at: 2)
        XCTAssertEqual(arranged.shown(on: .right, onBudPage: false), [.files])
        XCTAssertEqual(arranged.shown(on: .left, onBudPage: false), [])
    }

    func testALayoutListingAPanelTwiceKeepsItsFirstPlaceOnly() throws {
        let text = "{\"left\":[\"files\",\"inside\",\"files\"],\"right\":[\"inside\",\"source\",\"source\"]}"
        let layout = try JSONDecoder().decode(PanelLayout.self, from: Data(text.utf8))
        XCTAssertEqual(layout.left, [.files, .inside])
        XCTAssertEqual(layout.right, [.source])
        XCTAssertEqual(layout.side(of: .inside), .left)
    }

    func testNoDropLineForAGapBesideThePanelInHand() {
        let layout = PanelLayout.standard
        let above = PanelDrag(panel: .inside, point: .zero, drop: PanelDrop(side: .right, gap: 1))
        let below = PanelDrag(panel: .inside, point: .zero, drop: PanelDrop(side: .right, gap: 2))
        XCTAssertNil(above.line(on: .inside, in: layout), "Its own gap")
        XCTAssertNil(below.line(on: .whereItLives, in: layout), "The gap after it")
        let further = PanelDrag(panel: .inside, point: .zero, drop: PanelDrop(side: .right, gap: 3))
        XCTAssertEqual(further.line(on: .linkedFrom, in: layout), .above)
        let across = PanelDrag(panel: .files, point: .zero, drop: PanelDrop(side: .right, gap: 1))
        XCTAssertEqual(across.line(on: .inside, in: layout), .above, "From the other side every gap counts")
        XCTAssertNil(PanelDrag(panel: .inside, point: .zero).line(on: .inside, in: layout))
    }

    func testResetLayoutRestoresTheStandardLayoutAndLeavesTheFolds() {
        var state = PanelState()
        state.layout.move(.files, to: .right, at: 0)
        state.layout.hide(.linkedFrom)
        state.toggle(.inside)
        XCTAssertNotEqual(state.layout, .standard)
        PanelMenuItem.reset.apply(to: &state, for: .files)
        XCTAssertEqual(state.layout, .standard)
        XCTAssertEqual(state.collapsed, [.source, .inside], "Folding is this device's and stays")
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
        let text = await store.fileText(of: bud.id)
        XCTAssertEqual(text, "---\nstate: open\npinned: true\n---\nAsk the host first.")
        let unknown = await store.fileText(of: UUID())
        XCTAssertNil(unknown)
    }
}
#endif
