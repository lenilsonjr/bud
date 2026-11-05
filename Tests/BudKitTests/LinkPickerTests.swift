import XCTest
@testable import BudKit

final class LinkPickerTests: XCTestCase {
    func testTheLinkBeingTypedIsTheLastOpenOne() {
        XCTAssertEqual(LinkPicker(typing: "Keep it under [[bud")?.query, "bud")
        XCTAssertEqual(LinkPicker(typing: "[[")?.query, "")
        XCTAssertEqual(LinkPicker(typing: "done [[A]] and [[Bu")?.query, "Bu")
        XCTAssertNil(LinkPicker(typing: "done [[A]]"))
        XCTAssertNil(LinkPicker(typing: "[[A|lab"), "a label is being written")
        XCTAssertNil(LinkPicker(typing: "[[A\nnext line"))
        XCTAssertNil(LinkPicker(typing: "![[embed"))
        XCTAssertNil(LinkPicker(typing: "one [ bracket"))
    }

    func testCandidatesHoldTheQueryThoseItStartsFirst() {
        let me = Bud(text: "Apartment hunt")
        let tree = Tree(buds: [me, Bud(text: "Bud logo options"), Bud(text: "Budget 2026"), Bud(text: "Rosebud"), Bud(text: "Other")])
        let picker = LinkPicker(typing: "[[bud")!
        XCTAssertEqual(picker.candidates(in: tree, excluding: me.id).map(\.text), ["Bud logo options", "Budget 2026", "Rosebud"])
        XCTAssertFalse(LinkPicker(typing: "[[")!.candidates(in: tree, excluding: me.id).contains { $0.id == me.id })
    }

    func testPickingWritesTheLinkWithOrWithoutALabel() {
        let picker = LinkPicker(typing: "Keep it under [[bud")!
        XCTAssertEqual(picker.complete("Keep it under [[bud", with: "Budget 2026"), "Keep it under [[Budget 2026]]")
        XCTAssertEqual(picker.complete("Keep it under [[bud", with: "Budget 2026", labelled: true), "Keep it under [[Budget 2026|bud]]")
        let empty = LinkPicker(typing: "See [[")!
        XCTAssertEqual(empty.complete("See [[", with: "X", labelled: true), "See [[X]]")
    }
}
