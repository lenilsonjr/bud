import XCTest
@testable import BudKit

final class SimulationTests: XCTestCase {
    private let dt = 1.0 / 60

    private func overlapping(_ layout: Layout) -> Bool {
        let ids = layout.order
        for i in ids.indices {
            for j in ids.indices where j > i {
                let a = layout.cards[ids[i]]!, b = layout.cards[ids[j]]!
                let s = Metrics.size(hub: a.hub), t = Metrics.size(hub: b.hub)
                if abs(a.position.x - b.position.x) < (s.width + t.width) / 2, abs(a.position.y - b.position.y) < (s.height + t.height) / 2 {
                    return true
                }
            }
        }
        return false
    }

    private func farthest(_ sim: Simulation) -> Double {
        sim.layout.cards.map { id, card in
            let p = sim.positions[id]!
            return Double(hypot(p.x - card.position.x, p.y - card.position.y))
        }.max() ?? 0
    }

    func testACardAtRestCostsNothing() {
        var sim = Simulation(layout: LayoutEngine.layout(of: Tree.seed(), center: rootID))
        XCTAssertTrue(sim.isAtRest)
        let before = sim.positions
        sim.step(dt: dt)
        XCTAssertEqual(sim.positions, before)
        XCTAssertTrue(sim.isAtRest)
    }

    func testADisplacedCardReturnsAndNothingOverlaps() throws {
        let tree = Tree.seed()
        var sim = Simulation(layout: LayoutEngine.layout(of: tree, center: rootID))
        let id = try XCTUnwrap(tree.children(of: rootID).first).id
        sim.displace(id, by: Vector(dx: 300, dy: 0))
        XCTAssertFalse(sim.isAtRest)
        for _ in 0..<200 { sim.step(dt: dt) }
        XCTAssertLessThan(farthest(sim), 1, "Every card is back within a point of its spot")
        XCTAssertFalse(overlapping(sim.current))
        XCTAssertTrue(sim.isAtRest)
    }

    func testACardDoesNotRingOnTheWayBack() throws {
        var tree = Tree()
        let only = tree.add("Only", todo: false, under: rootID)
        var sim = Simulation(layout: LayoutEngine.layout(of: tree, center: rootID))
        sim.displace(only.id, by: Vector(dx: 300, dy: -120))
        var last = Double.infinity
        for _ in 0..<200 {
            sim.step(dt: dt)
            let rest = try XCTUnwrap(sim.layout.cards[only.id]).position
            let p = try XCTUnwrap(sim.positions[only.id])
            let d = Double(hypot(p.x - rest.x, p.y - rest.y))
            XCTAssertLessThanOrEqual(d, last + 1e-9, "The distance only shrinks")
            last = d
        }
    }

    func testACentreChangeSettlesWithinOneAndAHalfSeconds() throws {
        let tree = Tree.seed()
        let newsletter = try XCTUnwrap(tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        var sim = Simulation(layout: LayoutEngine.layout(of: tree, center: rootID))
        sim.retarget(to: LayoutEngine.layout(of: tree, center: newsletter.id))
        XCTAssertGreaterThan(farthest(sim), 50, "Cards start where they were")
        for _ in 0..<90 { sim.step(dt: dt) }
        XCTAssertLessThan(farthest(sim), 1)
        for _ in 0..<200 { sim.step(dt: dt) }
        XCTAssertFalse(overlapping(sim.current))
    }

    func testANewBudGrowsFromItsParent() throws {
        var tree = Tree.seed()
        let newsletter = try XCTUnwrap(tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        var sim = Simulation(layout: LayoutEngine.layout(of: tree, center: rootID))
        let bud = tree.add("Fresh", todo: false, under: newsletter.id)
        sim.retarget(to: LayoutEngine.layout(of: tree, center: rootID))
        XCTAssertEqual(sim.positions[bud.id], sim.positions[newsletter.id])
        for _ in 0..<200 { sim.step(dt: dt) }
        XCTAssertLessThan(farthest(sim), 1)
        XCTAssertFalse(overlapping(sim.current))
    }

    func testAHeldCardStaysPutUntilReleased() throws {
        let tree = Tree.seed()
        var sim = Simulation(layout: LayoutEngine.layout(of: tree, center: rootID))
        let id = try XCTUnwrap(tree.children(of: rootID).first).id
        let spot = CGPoint(x: 400, y: 300)
        sim.hold(id, at: spot)
        for _ in 0..<60 { sim.step(dt: dt) }
        XCTAssertEqual(sim.positions[id], spot)
        XCTAssertFalse(sim.isAtRest)
        sim.release(id)
        for _ in 0..<300 { sim.step(dt: dt) }
        XCTAssertLessThan(farthest(sim), 1)
        XCTAssertFalse(overlapping(sim.current))
    }

    func testACardDraggedOntoANeighbourPushesItAndBothSettle() throws {
        let tree = Tree.seed()
        var sim = Simulation(layout: LayoutEngine.layout(of: tree, center: rootID))
        let kids = tree.children(of: rootID)
        let a = try XCTUnwrap(kids.first).id, b = try XCTUnwrap(kids.dropFirst().first).id
        let target = try XCTUnwrap(sim.positions[b])
        let before = try XCTUnwrap(sim.positions[b])
        sim.displace(a, by: Vector(dx: Double(target.x - sim.positions[a]!.x), dy: Double(target.y - sim.positions[a]!.y)))
        sim.step(dt: dt)
        let pushed = try XCTUnwrap(sim.positions[b])
        XCTAssertNotEqual(pushed, before, "The neighbour is nudged while the spring runs")
        for _ in 0..<300 { sim.step(dt: dt) }
        XCTAssertLessThan(farthest(sim), 1)
        XCTAssertFalse(overlapping(sim.current))
        XCTAssertTrue(sim.isAtRest)
    }

    func testARetargetMidMotionDropsGoneCardsAndLetsGoOfAHeldOne() throws {
        var tree = Tree.seed()
        var sim = Simulation(layout: LayoutEngine.layout(of: tree, center: rootID))
        let kids = tree.children(of: rootID)
        let held = try XCTUnwrap(kids.first).id, other = try XCTUnwrap(kids.last).id
        sim.hold(held, at: CGPoint(x: 500, y: 400))
        sim.displace(other, by: Vector(dx: 80, dy: 0))
        sim.step(dt: dt)
        tree.remove(held)
        sim.retarget(to: LayoutEngine.layout(of: tree, center: rootID))
        XCTAssertNil(sim.positions[held])
        for _ in 0..<300 { sim.step(dt: dt) }
        XCTAssertLessThan(farthest(sim), 1, "Nothing is left held, so every card settles")
        XCTAssertTrue(sim.isAtRest)
        XCTAssertFalse(overlapping(sim.current))
    }

    func testTheLinesFollowTheMovingCards() throws {
        let tree = Tree.seed()
        var sim = Simulation(layout: LayoutEngine.layout(of: tree, center: rootID))
        let id = try XCTUnwrap(tree.children(of: rootID).first).id
        sim.displace(id, by: Vector(dx: 50, dy: 50))
        XCTAssertEqual(sim.current.position(of: id), sim.positions[id])
        XCTAssertEqual(sim.current.edges, sim.layout.edges, "Same edges, drawn between the live positions")
    }
}
