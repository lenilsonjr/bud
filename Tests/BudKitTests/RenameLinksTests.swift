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

    func testTakingAnotherBudsTitleKeepsItsLinks() {
        let foo = Bud(text: "Foo")
        let home = Bud(text: "Home")
        let bar = Bud(text: "Bar", parent: home.id)
        let z = Bud(text: "Z", body: "[[Bar]] and [[Foo]]")
        let tree = Tree(buds: [foo, home, bar, z])
        XCTAssertEqual(tree.relinked(renaming: foo.id, to: "Bar"), [z.id: "[[Home/Bar]] and [[Bar]]"])
    }

    func testRenamingAFolderKeepsPathLinksUnderIt() {
        let home = Bud(text: "Home")
        let twin = Bud(text: "Twin", parent: home.id)
        let w = Bud(text: "W", body: "[[Home/Twin]]")
        let tree = Tree(buds: [home, twin, Bud(text: "Twin"), w])
        XCTAssertEqual(tree.relinked(renaming: home.id, to: "House"), [w.id: "[[House/Twin]]"])
    }

    func testTitlesALinkCannotCarryRewriteNothing() {
        let a = Bud(text: "A")
        let tree = Tree(buds: [a, Bud(text: "B", body: "[[A]]")])
        for title in ["C# notes", "a|b", "x]]y", "a/b"] { XCTAssertEqual(tree.relinked(renaming: a.id, to: title), [:], title) }
    }
}
