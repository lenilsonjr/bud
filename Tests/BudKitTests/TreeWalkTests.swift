import XCTest
@testable import BudKit

final class TreeWalkTests: XCTestCase {
    /// A tree of thousands with ties in order, read the old way: each bud before its children,
    /// siblings by order then id.
    func testAWalkOfThousandsReadsInTheSameOrderAsOneChildAtATime() {
        var generator = Seeded(state: 0x5EED)
        var buds: [Bud] = []
        for n in 0..<3000 {
            let parent = buds.isEmpty || n % 7 == 0 ? rootID : buds[Int.random(in: 0..<buds.count, using: &generator)].id
            buds.append(Bud(text: "Bud \(n)", state: n % 3 == 0 ? .open : nil, parent: parent, order: Double(n % 5)))
        }
        let tree = Tree(buds: buds)
        func reference(_ id: UUID) -> [Bud] {
            tree.children(of: id).flatMap { [$0] + reference($0.id) }
        }
        let some = buds[Int.random(in: 0..<buds.count, using: &generator)].id
        for id in [rootID, buds[0].id, some] {
            XCTAssertEqual(tree.walk(under: id).map(\.id), reference(id).map(\.id))
            XCTAssertEqual(tree.descendants(of: id).sorted { $0.uuidString < $1.uuidString },
                           reference(id).map(\.id).sorted { $0.uuidString < $1.uuidString })
            XCTAssertEqual(tree.openCount(under: id), reference(id).filter { $0.state == .open }.count)
        }
    }

    func testAParentLoopEndsTheWalk() {
        let a = UUID(), b = UUID()
        let tree = Tree(buds: [Bud(id: a, text: "A", parent: b), Bud(id: b, text: "B", parent: a)])
        XCTAssertEqual(tree.walk(under: a).map(\.id), [b])
        XCTAssertEqual(tree.descendants(of: a), [b])
    }
}

/// A fixed sequence, so a failing tree can be built again.
private struct Seeded: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
