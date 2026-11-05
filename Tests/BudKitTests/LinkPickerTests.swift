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

    func testThePickerStaysOutOfCodeAndEarlierLines() {
        XCTAssertNil(LinkPicker(typing: "`[[x`"), "inside a code span")
        XCTAssertEqual(LinkPicker(typing: "`[[x")?.query, "x", "a lone backtick is plain text")
        XCTAssertNil(LinkPicker(typing: "```\n[[x"))
        XCTAssertEqual(LinkPicker(typing: "`code` then [[x")?.query, "x")
        XCTAssertNil(LinkPicker(typing: "See [[\nlater line"))
    }

    func testAnEditCountsOnlyAtTheOpenLink() {
        let picker = LinkPicker(typing: "Intro\nSee [[b")!
        XCTAssertTrue(picker.edited(from: "Intro\nSee [[", to: "Intro\nSee [[b"))
        XCTAssertTrue(picker.edited(from: "Intro\nSee [[bu", to: "Intro\nSee [[b"))
        XCTAssertFalse(picker.edited(from: "Intr\nSee [[b", to: "Intro\nSee [[b"), "typed earlier in the body")
        XCTAssertFalse(picker.edited(from: "Intro\nSee [[b", to: "Intro\nSee [[b"))
    }

    func testASharedTitleLinksByPathAndCutTitlesAreLeftOut() {
        let a = Bud(text: "Home")
        let b = Bud(text: "Work")
        let notesA = Bud(text: "Notes", parent: a.id)
        let notesB = Bud(text: "Notes", parent: b.id)
        let sharp = Bud(text: "C# notes")
        let tree = Tree(buds: [a, b, notesA, notesB, sharp])
        XCTAssertEqual(LinkPicker.target(for: notesA, in: tree), "Home/Notes")
        XCTAssertEqual(tree.resolve("Home/Notes"), notesA.id)
        XCTAssertEqual(LinkPicker.target(for: a, in: tree), "Home")
        XCTAssertFalse(LinkPicker(typing: "[[notes")!.candidates(in: tree, excluding: a.id).contains { $0.id == sharp.id })
    }
}
