import XCTest
@testable import BudKit

final class LinksTests: XCTestCase {
    func testLinksReadTargetsAndLabelsOutsideCode() {
        let body = "See [[Apartment hunt]] and [[Budget 2026#Rent|the budget]].\n`[[In code]]` ![[Embed]] [[]]\n```\n[[Fenced]]\n```\n[[Last]]"
        XCTAssertEqual(BudLinks.parse(body).map(\.target), ["Apartment hunt", "Budget 2026", "Last"])
        XCTAssertEqual(BudLinks.parse(body).map(\.shown), ["Apartment hunt", "the budget", "Last"])
    }

    func testTargetsResolveByTitleThenInAnyCaseAndNeverTwice() {
        let a = Bud(text: "Apartment hunt")
        let b = Bud(text: "Twin")
        let c = Bud(text: "twin")
        let d = Bud(text: "Other")
        let e = Bud(text: "OTHER", parent: d.id)
        let tree = Tree(buds: [a, b, c, d, e])
        XCTAssertEqual(tree.resolve("Apartment hunt"), a.id)
        XCTAssertEqual(tree.resolve("apartment HUNT"), a.id)
        XCTAssertEqual(tree.resolve("Twin"), b.id, "an exact title wins over another case")
        XCTAssertNil(tree.resolve("TWIN"), "two buds in any case name no bud")
        XCTAssertNil(tree.resolve("Nowhere"))
    }

    func testBacklinksShowTheLinkingBudOnceWithItsSentence() {
        let target = Bud(text: "Apartment hunt")
        let board = Bud(text: "Living room board", body: "Ideas first. Measure the walls once [[Apartment hunt]] lands a place. Then paint.\nAgain [[apartment hunt]].")
        let budget = Bud(text: "Budget 2026", body: "- Rent is whatever [[Apartment hunt|the hunt]] ends at, about €1,400 a month")
        let other = Bud(text: "Elsewhere", body: "[[Something else]] and `[[Apartment hunt]]`")
        let tree = Tree(buds: [target, board, budget, other])
        XCTAssertEqual(tree.backlinks(to: target.id), [
            Backlink(from: board.id, sentence: "Measure the walls once Apartment hunt lands a place.", shown: "Apartment hunt"),
            Backlink(from: budget.id, sentence: "Rent is whatever the hunt ends at, about €1,400 a month", shown: "the hunt"),
        ])
    }

    func testAPlantedBudsSourceIsNotALinkedFromRow() {
        // A bud planted from a link keeps where it came from as `source`, which is no body link.
        let parent = Bud(text: "Moving")
        let planted = Bud(text: "Neighborhood brief", parent: parent.id, source: "Moving")
        let tree = Tree(buds: [parent, planted])
        XCTAssertEqual(tree.backlinks(to: parent.id), [])
    }

    func testABudsLinkToItselfIsNoBacklink() {
        let solo = Bud(text: "Solo", body: "Back to [[Solo]].")
        XCTAssertEqual(Tree(buds: [solo]).backlinks(to: solo.id), [])
    }
}
