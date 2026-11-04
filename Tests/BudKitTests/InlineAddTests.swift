import XCTest
@testable import BudKit

final class InlineAddTests: XCTestCase {
    private let a = UUID()
    private let b = UUID()

    func testPlantingEmptiesTheBarAndStaysOnTheLevel() {
        var bar = InlineAdd(under: rootID, todo: false)
        bar.text = "  A new thread  "
        XCTAssertEqual(bar.line, "A new thread")
        bar.planted(a)
        XCTAssertEqual(bar.text, "")
        XCTAssertNil(bar.line)
        XCTAssertEqual(bar.parent, rootID)
        XCTAssertTrue(bar.canNest)
        XCTAssertFalse(bar.canRise)
    }

    func testTabGoesDownUnderTheLastBudAndShiftTabComesBack() {
        var bar = InlineAdd(under: rootID, todo: false)
        XCTAssertFalse(bar.nest(todo: true), "Nothing planted yet, nothing to go down into")
        bar.planted(a)
        XCTAssertTrue(bar.nest(todo: true))
        XCTAssertEqual(bar.parent, a)
        XCTAssertTrue(bar.todo)
        XCTAssertFalse(bar.canNest)
        bar.planted(b)
        XCTAssertTrue(bar.rise(todo: false))
        XCTAssertEqual(bar.parent, rootID)
        XCTAssertFalse(bar.todo)
        XCTAssertTrue(bar.canNest, "Back up, Tab goes down into the same bud again")
        XCTAssertTrue(bar.nest(todo: true))
        XCTAssertEqual(bar.parent, a)
        XCTAssertTrue(bar.rise(todo: false))
        XCTAssertFalse(bar.rise(todo: false), "Already at the level it started on")
    }

    func testTheBarSitsUnderTheNearestCardTheCanvasShows() {
        var t = Tree.seed()
        let thread = t.children(of: rootID)[0]
        let deep = t.add("Deep", todo: false, under: t.add("Middle", todo: false, under: t.children(of: thread.id)[0].id).id)
        let layout = LayoutEngine.layout(of: t, center: rootID)
        XCTAssertEqual(InlineAdd(under: rootID, todo: false).anchor(in: layout, tree: t), rootID)
        XCTAssertEqual(InlineAdd(under: thread.id, todo: false).anchor(in: layout, tree: t), thread.id)
        let nearest = ([deep.id] + t.ancestors(of: deep.id)).first { layout.cards[$0] != nil }
        XCTAssertNotNil(nearest)
        XCTAssertEqual(InlineAdd(under: deep.id, todo: false).anchor(in: layout, tree: t), nearest, "The nearest card above it the canvas shows")
    }

    func testThePlaceholderNamesWhereTheLineLands() {
        let t = Tree.seed()
        let thread = t.children(of: rootID)[0]
        XCTAssertEqual(InlineAdd(under: rootID, todo: false).placeholder(in: t), "Add a thread")
        XCTAssertEqual(InlineAdd(under: thread.id, todo: false).placeholder(in: t), "Add under \(thread.text)")
    }
}
