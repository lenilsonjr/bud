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

final class NextStepTests: XCTestCase {
    func testNextStepIsTheFirstOpenTodoInReadingOrder() throws {
        var t = Tree.seed()
        let newsletter = try XCTUnwrap(t.children(of: rootID).first { $0.text == "Launch the newsletter" })
        let name = try XCTUnwrap(t.children(of: newsletter.id).first { $0.text == "Pick a name" })
        XCTAssertEqual(t.nextStep(under: rootID)?.id, newsletter.id, "The first open to-do at the top is the next step")
        XCTAssertEqual(t.nextStep(under: newsletter.id)?.id, name.id, "Inside a bud, its first open child comes first")
        t.toggle(name.id)
        XCTAssertNotEqual(t.nextStep(under: newsletter.id)?.id, name.id, "A done to-do is never the next step")
        XCTAssertEqual(t.nextStep(under: newsletter.id)?.parent, name.id, "Its open children come before the next sibling")
        let note = t.add("Just a note", todo: false, under: rootID)
        XCTAssertNil(t.nextStep(under: note.id), "A note with nothing inside has no next step")
        XCTAssertEqual(t.walk(under: rootID).count, t.descendants(of: rootID).count)
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
        XCTAssertEqual(layout.cards.count, tree.buds.count + 1, "Nothing is hidden")
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
        for bud in tree.buds where bud.parent != rootID {
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
        XCTAssertEqual(layout.cards.count, tree.buds.count + 1)
        XCTAssertTrue(layout.edges.contains(Edge(from: newsletter.id, to: apartment.id)))
    }

    func testCrowdedBudsGrowOutwardAndStayClear() {
        var tree = Tree.seed()
        let newsletter = tree.children(of: rootID).first { $0.text == "Launch the newsletter" }!
        let review = tree.add("Review", todo: true, under: newsletter.id)
        for i in 0..<40 { tree.add("Detail \(i)", todo: false, under: review.id) }
        for i in 0..<20 { tree.add("Thread \(i)", todo: false, under: rootID) }
        let layout = LayoutEngine.layout(of: tree, center: rootID)
        XCTAssertEqual(layout.cards.count, tree.buds.count + 1)
        XCTAssertTrue(overlaps(layout).isEmpty, "Still no overlaps with a crowded web")
        XCTAssertGreaterThan(layout.orbits[review.id]!.rx, layout.orbits[rootID]!.rx, "A crowded bud grows its own orbit outward instead of shrinking its children")
    }
}
