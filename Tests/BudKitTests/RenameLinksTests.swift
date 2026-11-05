import XCTest
@testable import BudKit

final class RenameLinksTests: XCTestCase {
    func testARenameRewritesTheLinksThatNamedTheBud() {
        let garden = Bud(text: "Garden")
        let a = Bud(text: "A", body: "See [[Garden]], [[garden#Roses|the roses]] and [[Other]].\r\n```\n[[Garden]]\n```\n`[[Garden]]` ![[Garden]]")
        let b = Bud(text: "B", body: "Nothing here.")
        let tree = Tree(buds: [garden, a, b, Bud(text: "Other")])
        XCTAssertEqual(tree.relinked(renaming: garden.id, to: "Backyard"), [
            a.id: "See [[Backyard]], [[Backyard#Roses|the roses]] and [[Other]].\r\n```\n[[Garden]]\n```\n`[[Garden]]` ![[Garden]]",
        ])
        XCTAssertEqual(tree.relinked(renaming: garden.id, to: "Garden"), [:])
    }

    func testANewTitleAnotherBudHasLinksByPath() {
        let home = Bud(text: "Home")
        let garden = Bud(text: "Garden", parent: home.id)
        let a = Bud(text: "A", body: "[[Garden]]")
        let tree = Tree(buds: [home, garden, a, Bud(text: "Notes")])
        XCTAssertEqual(tree.relinked(renaming: garden.id, to: "Notes"), [a.id: "[[Home/Notes]]"])
    }

    func testLinksThatNamedNoBudStayAlone() {
        let one = Bud(text: "Twin")
        let two = Bud(text: "Twin")
        let a = Bud(text: "A", body: "[[Twin]]")
        XCTAssertEqual(Tree(buds: [one, two, a]).relinked(renaming: one.id, to: "Single"), [:])
    }
}
