import XCTest
@testable import BudKit

final class LinkGraphTests: XCTestCase {
    func testTheGraphHoldsEachResolvedLinkOnceEachWay() {
        let a = Bud(text: "A", body: "[[B]], [[B|again]], [[C]], [[Nowhere]] and [[A]]")
        let b = Bud(text: "B", body: "[[A]]")
        let c = Bud(text: "C")
        let graph = LinkGraph(Tree(buds: [a, b, c]))
        XCTAssertEqual(graph.out[a.id], [b.id, c.id], "once each, never itself, never nowhere")
        XCTAssertEqual(graph.into[b.id], [a.id])
        XCTAssertEqual(graph.into[a.id], [b.id])
        XCTAssertNil(graph.out[c.id])
        let around = graph.around(a.id)
        XCTAssertEqual(around.map(\.other), [b.id, c.id], "B links both ways and shows once")
        XCTAssertEqual(around.map(\.outgoing), [true, true])
        XCTAssertEqual(graph.around(c.id).map(\.outgoing), [false])
    }

    func testALinkLeavesACardAtItsEdge() {
        let center = CGPoint(x: 100, y: 100), size = CGSize(width: 180, height: 80)
        XCTAssertEqual(LinkGeometry.edge(of: center, size: size, toward: CGPoint(x: 400, y: 100)), CGPoint(x: 190, y: 100))
        XCTAssertEqual(LinkGeometry.edge(of: center, size: size, toward: CGPoint(x: 100, y: -300)), CGPoint(x: 100, y: 60))
        XCTAssertEqual(LinkGeometry.edge(of: center, size: size, toward: CGPoint(x: 120, y: 100)), CGPoint(x: 120, y: 100), "a point inside stays")
        XCTAssertEqual(LinkGeometry.edge(of: center, size: size, toward: center), center)
    }

    func testTheCurveBowsAndGhostsSitAwayFromTheLitCard() {
        XCTAssertEqual(LinkGeometry.bow(from: .zero, to: CGPoint(x: 100, y: 0)), CGPoint(x: 50, y: 25))
        let size = CGSize(width: 1000, height: 500)
        XCTAssertEqual(LinkGeometry.ghostSlots(count: 1, lit: CGPoint(x: 200, y: 200), in: size, inset: 120), [CGPoint(x: 880, y: 250)])
        XCTAssertEqual(LinkGeometry.ghostSlots(count: 2, lit: CGPoint(x: 800, y: 200), in: size, inset: 120), [CGPoint(x: 120, y: 100), CGPoint(x: 120, y: 400)])
        XCTAssertEqual(LinkGeometry.ghostSlots(count: 0, lit: .zero, in: size, inset: 1), [])
    }
}
