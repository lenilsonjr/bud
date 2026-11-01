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
