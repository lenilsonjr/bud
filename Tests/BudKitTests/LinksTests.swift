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
            Backlink(from: budget.id, sentence: "Rent is whatever the hunt ends at, about €1,400 a month", mark: 17..<25),
            Backlink(from: board.id, sentence: "Measure the walls once Apartment hunt lands a place.", mark: 23..<37),
        ])
    }

    func testCodeAndFencesHoldNoLinksTheWayTheCoreReadsThem() {
        XCTAssertEqual(BudLinks.parse("Don`t forget [[Plan]]").map(\.target), ["Plan"], "an unpaired backtick is plain text")
        XCTAssertEqual(BudLinks.parse("``[[x]] ` [[y]]`` then [[z]]").map(\.target), ["z"])
        XCTAssertEqual(BudLinks.parse("~~~\n[[Or this]]\n~~~\n[[After]]").map(\.target), ["After"])
        XCTAssertEqual(BudLinks.parse("````\n```\n[[Inside]]\n```rust\n````\n[[Outside]]").map(\.target), ["Outside"])
        XCTAssertEqual(BudLinks.parse("```swift\ncode\n```swift\n[[Outside]]").map(\.target), [])
    }

    func testTheMarkIsTheLinkAndTheSentenceKeepsItsCode() {
        let target = Bud(text: "X")
        let tree = Tree(buds: [
            target,
            Bud(text: "A", body: "Write it down, as [[X|it]] says."),
            Bud(text: "B", body: "Run `make` then see [[X]]."),
            Bud(text: "C", body: "See [[Y. Z|a. b]] and then [[X]] ok"),
            Bud(text: "D", body: "> 10) quoted [[x]] here"),
        ])
        let rows = tree.backlinks(to: target.id)
        func marked(_ row: Backlink) -> String {
            let chars = Array(row.sentence)
            return String(chars[row.mark])
        }
        XCTAssertEqual(rows.map(\.sentence), ["Write it down, as it says.", "Run `make` then see X.", "See a. b and then X ok", "quoted x here"])
        XCTAssertEqual(rows.map(marked), ["it", "X", "X", "x"])
        XCTAssertEqual(rows[0].mark, 18..<20)
    }

    func testAPathNamesABudToo() {
        let launch = Bud(text: "Launch")
        let list = Bud(text: "Welcome list", parent: launch.id)
        let tree = Tree(buds: [launch, list, Bud(text: "Note", body: "See [[Launch/Welcome list.md]].")])
        XCTAssertEqual(tree.resolve("Launch/Welcome list"), list.id)
        XCTAssertEqual(tree.backlinks(to: list.id).map(\.sentence), ["See Launch/Welcome list.md."])
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
