import XCTest
@testable import BudKit

final class TreeTests: XCTestCase {
    func testSeedAndOperations() throws {
        var t = Tree.seed()
        XCTAssertEqual(t.children(of: rootID).count, 7)
        let newsletter = try XCTUnwrap(t.children(of: rootID).first { $0.text == "Launch the newsletter" })
        XCTAssertTrue(newsletter.isTodo)
        XCTAssertEqual(t.ancestors(of: newsletter.id), [rootID])
        let apartment = try XCTUnwrap(t.children(of: newsletter.id).first)
        XCTAssertEqual(t.ancestors(of: apartment.id), [newsletter.id, rootID])
        XCTAssertEqual(t.title(of: rootID), "Everything")

        let note = t.add("Just a thought", todo: false, under: apartment.id)
        XCTAssertFalse(note.isTodo)
        XCTAssertEqual(t.children(of: apartment.id).last?.id, note.id, "New buds go last among their siblings")
        t.toggle(note.id)
        XCTAssertNil(t.bud(note.id)?.state, "Toggling a note does nothing")
        t.update(note.id, text: "Now a task", todo: true)
        XCTAssertEqual(t.bud(note.id)?.state, .open)
        t.toggle(note.id)
        XCTAssertEqual(t.bud(note.id)?.state, .done)
        XCTAssertTrue(t.openCount(under: rootID) > 0)

        let before = t.buds.count
        let gone = t.descendants(of: newsletter.id).count + 1
        t.remove(newsletter.id)
        XCTAssertEqual(t.buds.count, before - gone, "Removing a bud removes its whole subtree")
        XCTAssertNil(t.bud(apartment.id))

        let data = try JSONEncoder().encode(t)
        let back = try JSONDecoder().decode(Tree.self, from: data)
        XCTAssertEqual(back, t)
    }
}

final class QuickAddTests: XCTestCase {
    func testTheKindFollowsTheParent() throws {
        let t = Tree.seed()
        let newsletter = try XCTUnwrap(t.children(of: rootID).first { $0.text == "Launch the newsletter" })
        XCTAssertFalse(t.suggestsTodo(under: rootID), "A note under the root")
        XCTAssertTrue(t.suggestsTodo(under: newsletter.id), "A to-do under a to-do")
        let note = try XCTUnwrap(t.walk(under: rootID).first { !$0.isTodo })
        XCTAssertFalse(t.suggestsTodo(under: note.id), "A note under a note")
    }

    #if canImport(Combine)
    @MainActor
    func testABlankLinePlantsNothingAndALineIsTrimmed() throws {
        let store = BudStore(fileURL: nil)
        let before = store.tree.children(of: rootID).count
        store.add("   ", todo: true, under: rootID)
        store.add("\n", todo: false, under: rootID)
        XCTAssertEqual(store.tree.children(of: rootID).count, before)
        store.add("  Water the fern  ", todo: true, under: rootID)
        let planted: Bud = try XCTUnwrap(store.tree.children(of: rootID).last)
        XCTAssertEqual(planted.text, "Water the fern")
        XCTAssertTrue(planted.isTodo)
        XCTAssertEqual(store.tree.children(of: rootID).count, before + 1)
    }
    #endif
}

final class OpenedCardTests: XCTestCase {
    func testStatusLabelAndPeek() throws {
        var t = Tree.seed()
        let newsletter = try XCTUnwrap(t.children(of: rootID).first { $0.text == "Launch the newsletter" })
        XCTAssertEqual(newsletter.statusLabel, "To-do")
        t.toggle(newsletter.id)
        XCTAssertEqual(t.bud(newsletter.id)?.statusLabel, "Done")
        let note = try XCTUnwrap(t.walk(under: rootID).first { !$0.isTodo })
        XCTAssertEqual(note.statusLabel, "Note")

        let titles = t.children(of: newsletter.id).map(\.text)
        XCTAssertEqual(t.peek(into: newsletter.id), Array(titles.prefix(3)), "Three titles, in reading order")
        XCTAssertEqual(t.peek(into: newsletter.id, limit: 1), [titles[0]])
        let leaf = try XCTUnwrap(t.walk(under: rootID).first { !t.hasChildren($0.id) })
        XCTAssertEqual(t.peek(into: leaf.id), [], "A leaf has nothing to peek at")
    }

    #if canImport(Combine)
    @MainActor
    func testOpenAsFileSwitchesToFilesOnThatBud() throws {
        let store = BudStore(fileURL: nil)
        let newsletter = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        let leaf = try XCTUnwrap(store.tree.walk(under: newsletter.id).first { !store.tree.hasChildren($0.id) })
        store.openAsFile(leaf.id)
        XCTAssertEqual(store.surface, .files)
        XCTAssertEqual(store.center, leaf.id, "The center is the selection in Files, a leaf included")
        XCTAssertEqual(store.layout.cards[leaf.id]?.role, .center)
    }
    #endif
}

final class OutlineTests: XCTestCase {
    func testOutlineShowsOnlyWhatIsExpanded() throws {
        let t = Tree.seed()
        let top = t.children(of: rootID)
        XCTAssertEqual(t.outline(expanded: []).map(\.id), top.map(\.id), "Closed: the top level only")
        XCTAssertTrue(t.outline(expanded: []).allSatisfy { $0.depth == 0 })

        let newsletter = try XCTUnwrap(top.first { $0.text == "Launch the newsletter" })
        let rows = t.outline(expanded: [newsletter.id])
        let kids = t.children(of: newsletter.id)
        let at = try XCTUnwrap(rows.firstIndex { $0.id == newsletter.id })
        XCTAssertEqual(rows[(at + 1)...(at + kids.count)].map(\.id), kids.map(\.id), "Children follow their parent")
        XCTAssertTrue(rows[(at + 1)...(at + kids.count)].allSatisfy { $0.depth == 1 })
        XCTAssertEqual(rows.count, top.count + kids.count, "Grandchildren stay hidden until their parent opens")

        let everything = t.outline(expanded: Set(t.buds.map(\.id)))
        XCTAssertEqual(everything.map(\.id), t.walk(under: rootID).map(\.id), "Fully open, the outline is the reading order")
    }
}

final class SearcherTests: XCTestCase {
    func testSubstringHitsCarryTheirTrailAndComeInReadingOrder() throws {
        let t = Tree.seed()
        let s = TreeSearcher(tree: t)
        XCTAssertEqual(s.search("   ").count, 0, "An empty query lists nothing; places stand in")

        let hits = s.search("news")
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(hits.first?.title, "Launch the newsletter", "The thread whose title matches comes first")
        XCTAssertEqual(hits.first?.trail, ["Everything"])
        XCTAssertEqual(s.search("NEWS").map(\.id), hits.map(\.id), "Case does not matter")

        let newsletter = try XCTUnwrap(t.children(of: rootID).first { $0.text == "Launch the newsletter" })
        let inside = try XCTUnwrap(t.children(of: newsletter.id).first)
        let deep = try XCTUnwrap(s.search(inside.text).first { $0.id == inside.id })
        XCTAssertEqual(deep.trailText, "Everything › Launch the newsletter")

        let all = s.search("e", limit: 5)
        XCTAssertEqual(all.count, 5, "The limit holds")
        XCTAssertEqual(all.map(\.id), Array(t.walk(under: rootID).filter { $0.text.lowercased().contains("e") }.prefix(5).map(\.id)))
    }

    func testPlacesAndLensesMatchByName() {
        XCTAssertEqual(Destination.matching(""), Destination.allCases, "Empty query: every place and lens")
        XCTAssertEqual(Destination.matching("to"), [.today, .todos])
        XCTAssertEqual(Destination.matching("xyz"), [])
        XCTAssertTrue(Destination.inbox.isPlace)
        XCTAssertFalse(Destination.pinned.isPlace)
    }
}

final class UndoTests: XCTestCase {
    func testAnUndoableRunsItsClosure() {
        final class Box: @unchecked Sendable { var ran = 0 }
        let box = Box()
        let action = Undoable(message: "Planted under Everything") { box.ran += 1 }
        XCTAssertEqual(action.message, "Planted under Everything")
        action.undo()
        XCTAssertEqual(box.ran, 1)
    }

    #if canImport(Combine)
    @MainActor
    func testTheToastShowsThenGoesOnUndoOrTimeOrTheNextOne() async throws {
        final class Box: @unchecked Sendable { var undone: [String] = [] }
        let box = Box()
        let center = ToastCenter(duration: .milliseconds(60))

        center.show(Undoable(message: "one") { box.undone.append("one") })
        XCTAssertEqual(center.current?.action.message, "one")
        center.undo()
        XCTAssertNil(center.current, "Undo drops the toast")
        XCTAssertEqual(box.undone, ["one"])

        center.show(Undoable(message: "two") { box.undone.append("two") })
        center.show(Undoable(message: "three") { box.undone.append("three") })
        XCTAssertEqual(center.current?.action.message, "three", "A new toast replaces the one before it")

        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(center.current, "Time takes the toast away")
        XCTAssertEqual(box.undone, ["one"], "Nothing undone on its own")
    }

    @MainActor
    func testPlantingOffersUndoThatRemovesTheBud() throws {
        let store = BudStore(fileURL: nil)
        let before = store.tree.children(of: rootID).count
        let planted = try XCTUnwrap(store.add("Water the fern", todo: true, under: rootID))
        XCTAssertEqual(store.toasts.current?.action.message, "Planted under Everything")
        store.toasts.undo()
        let exp = expectation(description: "removed on the main actor")
        Task { @MainActor in
            XCTAssertNil(store.tree.bud(planted.id))
            XCTAssertEqual(store.tree.children(of: rootID).count, before)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }
    #endif
}

final class LightTests: XCTestCase {
    func testTheCurrentOrbitIsLitAndTheRestDimsUnlessLifted() {
        XCTAssertEqual(lightLevel(role: .center, lifted: false), 1)
        XCTAssertEqual(lightLevel(role: .ring, lifted: false), 1)
        for role in [CardRole.deep, .ghost, .kin] {
            XCTAssertEqual(lightLevel(role: role, lifted: false), 0.35, "\(role) rests dim")
            XCTAssertEqual(lightLevel(role: role, lifted: true), 1, "\(role) lifts under the light")
        }
    }

    func testAnOrbitIsTheParentAndTheSiblings() throws {
        let t = Tree.seed()
        let newsletter = try XCTUnwrap(t.children(of: rootID).first { $0.text == "Launch the newsletter" })
        let kids = t.children(of: newsletter.id)
        let first = try XCTUnwrap(kids.first)
        let orbit = t.orbit(of: first.id)
        XCTAssertTrue(orbit.contains(newsletter.id), "The parent")
        XCTAssertEqual(orbit.intersection(kids.map(\.id)).count, kids.count, "Every sibling, itself included")
        XCTAssertFalse(orbit.contains(rootID), "Not the grandparent")
        XCTAssertEqual(t.orbit(of: rootID), [rootID], "The root stands alone")
        XCTAssertEqual(t.orbit(of: newsletter.id), Set(t.children(of: rootID).map(\.id)).union([rootID]))
    }
}

final class PropertiesTests: XCTestCase {
    func testTheSeedCarriesBodiesDatesAndAPin() throws {
        let t = Tree.seed()
        let newsletter = try XCTUnwrap(t.children(of: rootID).first { $0.text == "Launch the newsletter" })
        XCTAssertTrue(newsletter.pinned)
        XCTAssertFalse(newsletter.body.isEmpty)
        let all = t.walk(under: rootID)
        XCTAssertEqual(all.filter { $0.due != nil }.count, 2, "Two due dates")
        XCTAssertEqual(all.filter { $0.when != nil }.count, 1, "One scheduled day")
        XCTAssertEqual(all.filter(\.pinned).count, 1)
        XCTAssertTrue(all.allSatisfy { $0.created <= Date() })
    }

    func testSmallMutationsSetEachProperty() throws {
        var t = Tree.seed()
        let bud = try XCTUnwrap(t.children(of: rootID).last)
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        t.setBody(bud.id, "A line below the title.")
        t.setWhen(bud.id, day)
        t.setDue(bud.id, day)
        t.setPinned(bud.id, true)
        let now = try XCTUnwrap(t.bud(bud.id))
        XCTAssertEqual(now.body, "A line below the title.")
        XCTAssertEqual(now.when, day)
        XCTAssertEqual(now.due, day)
        XCTAssertTrue(now.pinned)
        t.setDue(bud.id, nil)
        XCTAssertNil(t.bud(bud.id)?.due)
        let before = t
        t.setBody(UUID(), "nowhere")
        XCTAssertEqual(t, before, "An unknown id changes nothing")
    }

    func testAFileSavedBeforeThePropertiesStillLoads() throws {
        let old = """
        {"buds":[{"id":"11111111-1111-1111-1111-111111111111","text":"Old bud","state":"open",
        "parent":"00000000-0000-0000-0000-000000000000","order":1}]}
        """
        let t = try JSONDecoder().decode(Tree.self, from: Data(old.utf8))
        let bud = try XCTUnwrap(t.buds.first)
        XCTAssertEqual(bud.text, "Old bud")
        XCTAssertEqual(bud.state, .open)
        XCTAssertEqual(bud.body, "")
        XCTAssertNil(bud.when)
        XCTAssertNil(bud.due)
        XCTAssertFalse(bud.pinned)
        XCTAssertLessThanOrEqual(bud.created.timeIntervalSinceNow, 1)

        let data = try JSONEncoder().encode(t)
        let again = try JSONDecoder().decode(Tree.self, from: data)
        XCTAssertEqual(again.buds.first?.id, bud.id, "What we write, we read back")
    }
}

final class LensTests: XCTestCase {
    func testTodayIsDueThenScheduledOverdueFirst() throws {
        var t = Tree()
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let thread = t.add("Thread", todo: true, under: rootID)
        let overdue = t.add("Overdue", todo: true, under: thread.id)
        let dueToday = t.add("Due today", todo: true, under: thread.id)
        let dueLater = t.add("Due later", todo: true, under: thread.id)
        let scheduled = t.add("Scheduled note", todo: false, under: thread.id)
        let both = t.add("Both", todo: true, under: thread.id)
        let done = t.add("Done and due", todo: true, under: thread.id)
        t.setDue(overdue.id, day.addingTimeInterval(-86_400 * 3))
        t.setDue(dueToday.id, day)
        t.setDue(dueLater.id, day.addingTimeInterval(86_400 * 2))
        t.setWhen(scheduled.id, day.addingTimeInterval(-3_600))
        t.setDue(both.id, day); t.setWhen(both.id, day)
        t.setDue(done.id, day); t.toggle(done.id)

        let today = t.today(on: day)
        XCTAssertEqual(today.due.map(\.text), ["Overdue", "Both", "Due today"], "Overdue first, then by due date, then by title")
        XCTAssertEqual(today.scheduled.map(\.id), [scheduled.id], "Scheduled, and Both shows only once")
        XCTAssertFalse(today.due.contains { $0.id == done.id }, "A done to-do leaves the lens")
        XCTAssertFalse(today.due.contains { $0.id == dueLater.id })
    }

    func testOpenTodosGroupByThreadAndPinnedListsThePins() throws {
        let t = Tree.seed()
        let groups = t.openTodos()
        XCTAssertEqual(groups.first?.thread.text, "Launch the newsletter")
        XCTAssertTrue(groups.allSatisfy { !$0.todos.isEmpty })
        XCTAssertTrue(groups.allSatisfy { $0.todos.allSatisfy { $0.state == .open } })
        XCTAssertFalse(groups.contains { $0.thread.text == "Routines" }, "A note thread with no to-dos has no group")
        XCTAssertEqual(groups.flatMap(\.todos).count, t.openCount(under: rootID), "Every open to-do appears once")
        XCTAssertEqual(t.pinned().map(\.text), ["Launch the newsletter"])
        let name = try XCTUnwrap(t.walk(under: rootID).first { $0.text == "Pick a name" })
        XCTAssertEqual(t.breadcrumb(of: name.id), ["Launch the newsletter"], "The root is left out")
    }
}

final class NextStepTests: XCTestCase {
    private func world() -> (Tree, UUID) {
        var t = Tree()
        let thread = t.add("Thread", todo: true, under: rootID)
        return (t, thread.id)
    }

    func testTheSoonestDueComesFirst() throws {
        var (t, thread) = world()
        let later = t.add("Due later", todo: true, under: thread)
        let soon = t.add("Due soon", todo: true, under: thread)
        let none = t.add("No date", todo: true, under: thread)
        t.setDue(later.id, Date(timeIntervalSince1970: 2_000_000))
        t.setDue(soon.id, Date(timeIntervalSince1970: 1_000_000))
        t.setWhen(none.id, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(t.nextStep(under: thread)?.id, soon.id, "A due date beats a scheduled day and no date")
    }

    func testThenTheSoonestScheduledDay() throws {
        var (t, thread) = world()
        let plain = t.add("Plain", todo: true, under: thread)
        let tomorrow = t.add("Tomorrow", todo: true, under: thread)
        let today = t.add("Today", todo: true, under: thread)
        t.setWhen(tomorrow.id, Date(timeIntervalSince1970: 2_000_000))
        t.setWhen(today.id, Date(timeIntervalSince1970: 1_000_000))
        XCTAssertEqual(t.nextStep(under: thread)?.id, today.id)
        XCTAssertNotEqual(t.nextStep(under: thread)?.id, plain.id, "No date comes after any date")
    }

    func testThenTheOldest() throws {
        var (t, thread) = world()
        let young = t.add("Young", todo: true, under: thread)
        let old = t.add("Old", todo: true, under: thread)
        t.buds[t.buds.firstIndex { $0.id == old.id }!].created = Date(timeIntervalSince1970: 100)
        t.buds[t.buds.firstIndex { $0.id == young.id }!].created = Date(timeIntervalSince1970: 200)
        XCTAssertEqual(t.nextStep(under: thread)?.id, old.id, "With no dates, the oldest open to-do is next")
    }

    func testDoneAndNotesNeverCountAndNilWhenNothingIsOpen() throws {
        var (t, thread) = world()
        let note = t.add("A note", todo: false, under: thread)
        let done = t.add("Done already", todo: true, under: thread)
        t.toggle(done.id)
        XCTAssertNil(t.nextStep(under: note.id))
        XCTAssertNil(t.nextStep(under: thread), "A note and a done to-do leave nothing to do")
        let open = t.add("Open", todo: true, under: note.id)
        XCTAssertEqual(t.nextStep(under: thread)?.id, open.id, "An open to-do deep inside counts")
        XCTAssertEqual(t.nextStep(under: rootID)?.id, thread, "At the root the thread itself is older than its child")
    }

    func testTheSeedPutsTheOverdueOneFirst() throws {
        let t = Tree.seed()
        XCTAssertEqual(t.nextStep(under: rootID)?.text, "Verify the address", "Overdue beats every other date")
    }
}

final class LayoutTests: XCTestCase {
    func overlaps(_ layout: Layout) -> [(UUID, UUID)] {
        var out: [(UUID, UUID)] = []
        let ids = layout.order
        for i in ids.indices {
            for j in ids.indices where j > i {
                let a = layout.cards[ids[i]]!, b = layout.cards[ids[j]]!
                let s = Metrics.size(of: ids[i]), t = Metrics.size(of: ids[j])
                if abs(a.position.x - b.position.x) < (s.width + t.width) / 2, abs(a.position.y - b.position.y) < (s.height + t.height) / 2 {
                    out.append((ids[i], ids[j]))
                }
            }
        }
        return out
    }

    func testEverythingIsOnTheCanvasAtFullSizeWithoutOverlaps() {
        let tree = Tree.seed()
        let layout = LayoutEngine.layout(of: tree, center: rootID)
        XCTAssertEqual(layout.cards.count, tree.walk(under: rootID).count + 1, "Nothing under the root is hidden")
        XCTAssertTrue(tree.inbox().allSatisfy { layout.cards[$0.id] == nil }, "The inbox is not on the canvas")
        XCTAssertEqual(layout.position(of: rootID), .zero)
        XCTAssertTrue(overlaps(layout).isEmpty, "No two cards overlap")
        let ring = layout.orbits[rootID]!
        for kid in tree.children(of: rootID) {
            let p = layout.position(of: kid.id)!
            let u = p.x / ring.rx, v = p.y / ring.ry
            XCTAssertEqual(Double(u * u + v * v), 1, accuracy: 1e-6, "The first layer sits on one ellipse around the hub")
            XCTAssertEqual(layout.cards[kid.id]?.role, .ring)
        }
        let first = tree.children(of: rootID).first!
        XCTAssertLessThan(layout.position(of: first.id)!.y, -ring.ry * 0.99, "The first thread sits at the top")
        XCTAssertLessThan(ring.ry, 320, "The first layer stays close enough to be in view")
        for bud in tree.walk(under: rootID) where bud.parent != rootID {
            let p = layout.position(of: bud.id)!
            XCTAssertGreaterThan(hypot(p.x, p.y), ring.ry * 0.9, "Deeper layers sprawl outward past the first ring")
            XCTAssertEqual(layout.cards[bud.id]?.role, .deep)
        }
    }

    func testCenteringABudBringsItsOrbitToTheMiddleAndTrailsAncestorsUpLeft() throws {
        let tree = Tree.seed()
        let newsletter = try XCTUnwrap(tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        let apartment = try XCTUnwrap(tree.children(of: newsletter.id).first)
        let layout = LayoutEngine.layout(of: tree, center: apartment.id)
        XCTAssertEqual(layout.position(of: apartment.id), .zero)
        XCTAssertEqual(layout.cards[newsletter.id]?.role, .ghost)
        XCTAssertEqual(layout.cards[rootID]?.role, .ghost)
        let g1 = layout.position(of: newsletter.id)!, g2 = layout.position(of: rootID)!
        XCTAssertTrue(g1.x < 0 && g1.y < 0, "The parent trails off up and to the left")
        XCTAssertGreaterThan(hypot(g2.x, g2.y), hypot(g1.x, g1.y), "and its own parent further still")
        for sibling in tree.children(of: newsletter.id) where sibling.id != apartment.id {
            XCTAssertEqual(layout.cards[sibling.id]?.role, .kin, "The rest of the world stays around the ghost")
        }
        XCTAssertTrue(overlaps(layout).isEmpty)
        XCTAssertEqual(layout.cards.count, tree.walk(under: rootID).count + 1)
        XCTAssertTrue(layout.edges.contains(Edge(from: newsletter.id, to: apartment.id)))
    }

    func testCrowdedBudsGrowOutwardAndStayClear() {
        var tree = Tree.seed()
        let newsletter = tree.children(of: rootID).first { $0.text == "Launch the newsletter" }!
        let review = tree.add("Review", todo: true, under: newsletter.id)
        for i in 0..<40 { tree.add("Detail \(i)", todo: false, under: review.id) }
        for i in 0..<20 { tree.add("Thread \(i)", todo: false, under: rootID) }
        let layout = LayoutEngine.layout(of: tree, center: rootID)
        XCTAssertEqual(layout.cards.count, tree.walk(under: rootID).count + 1)
        XCTAssertTrue(overlaps(layout).isEmpty, "Still no overlaps with a crowded web")
        XCTAssertGreaterThan(layout.orbits[review.id]!.rx, layout.orbits[rootID]!.rx, "A crowded bud grows its own orbit outward instead of shrinking its children")
    }
}
