import XCTest
@testable import BudKit

final class TagsTests: XCTestCase {
    func testBodyTagsStartAWordAndStayOutOfCodeAndHeadingsLikeTheCore() {
        let body = "# Heading\n## Another\nBuy #milk, #eggs, not page#part, [see](#setup), #- or #1.\n`#code` then #après-ski #a/b/\n```\n#fenced\n```\n[[Note#Part]] #end"
        XCTAssertEqual(BudTags.inBody(body), ["milk", "eggs", "après-ski", "a/b", "end"])
        XCTAssertEqual(BudTags.inBody("one\r\n#two\r\n"), ["two"])
    }

    func testCleanTakesTheHashAndTrailingSlashAndRefusesWhatIsNoTag() {
        XCTAssertEqual(BudTags.clean("#Home/"), "Home")
        XCTAssertNil(BudTags.clean("#1"))
        XCTAssertNil(BudTags.clean("two words"))
    }

    func testABudCarriesItsListAndBodyTagsOnceInAnyCase() {
        let bud = Bud(text: "Groceries", body: "Milk for the #Home fridge #weekly", tags: ["home", "errands"])
        XCTAssertEqual(bud.allTags, ["home", "errands", "weekly"])
        XCTAssertTrue(bud.carries("HOME"))
        XCTAssertFalse(bud.carries("garden"))
    }

    func testCountsAreMostUsedFirstInTheSpellingMostBudsUse() {
        let tree = Tree(buds: [
            Bud(text: "A", tags: ["home"]),
            Bud(text: "B", body: "#Home"),
            Bud(text: "C", body: "#home #garden"),
        ])
        XCTAssertEqual(tree.tagCounts(), [TagCount(tag: "home", buds: 3), TagCount(tag: "garden", buds: 1)])
    }

    func testAddAndRemoveTouchOnlyTheBudsOwnList() {
        let bud = Bud(text: "Groceries", body: "#home")
        var tree = Tree(buds: [bud])
        tree.addTag(bud.id, "HOME")
        XCTAssertEqual(tree.bud(bud.id)?.tags, [], "the body carries it already")
        tree.addTag(bud.id, "#errands")
        XCTAssertEqual(tree.bud(bud.id)?.tags, ["errands"])
        tree.removeTag(bud.id, "Errands")
        tree.removeTag(bud.id, "home")
        XCTAssertEqual(tree.bud(bud.id)?.tags, [])
        XCTAssertEqual(tree.bud(bud.id)?.body, "#home")
    }

    func testARenameReachesListsBodiesAndNestedTagsAndMergesOnlyWhatItRenamed() {
        let a = Bud(text: "A", body: "Milk #home, #home/kitchen, not #homely or `#home`\r\nnext #Home", tags: ["Home", "chores", "x", "X"])
        let b = Bud(text: "B", body: "nothing")
        var tree = Tree(buds: [a, b])
        XCTAssertEqual(tree.renameTag("home", to: "chores"), [a.id])
        XCTAssertEqual(tree.bud(a.id)?.tags, ["chores", "x", "X"])
        XCTAssertEqual(tree.bud(a.id)?.body, "Milk #chores, #chores/kitchen, not #homely or `#home`\r\nnext #chores")
    }

    func testTheMemoryVaultUndoesARenameWithTheTextItHandedOver() async throws {
        let bud = Bud(text: "A", body: "#home", tags: ["home"])
        let vault = MemoryVault(tree: Tree(buds: [bud]))
        let edits = try await vault.renameTag("home", to: "house")
        XCTAssertEqual(edits.map(\.path), [bud.id.uuidString])
        var now = await vault.tree.bud(bud.id)
        XCTAssertEqual(now?.tags, ["house"])
        XCTAssertEqual(now?.body, "#house")
        try await vault.setText(bud.path, edits[0].before)
        now = await vault.tree.bud(bud.id)
        XCTAssertEqual(now?.tags, ["home"])
        XCTAssertEqual(now?.body, "#home")
    }

    func testRecordsCarryTheList() {
        let bud = Bud(text: "A", tags: ["home"])
        let tree = Tree(buds: [bud])
        XCTAssertEqual(Tree(records: tree.records()).bud(bud.id)?.tags, ["home"])
    }

    func testThePickerOffersTagsInAnyCaseWithCountsAndCreatesLast() {
        let counts = [TagCount(tag: "home", buds: 3), TagCount(tag: "finance", buds: 4), TagCount(tag: "finland trip", buds: 1), TagCount(tag: "refine", buds: 1)]
        XCTAssertEqual(TagChoices.rows(for: "Home", in: counts, excluding: []), [.tag(counts[0])])
        XCTAssertEqual(
            TagChoices.rows(for: "#fin", in: counts, excluding: []),
            [.tag(counts[1]), .tag(counts[2]), .tag(counts[3]), .create("fin")]
        )
        XCTAssertEqual(TagChoices.rows(for: "home", in: counts, excluding: ["HOME"]), [], "carried already")
        XCTAssertEqual(TagChoices.rows(for: "two words", in: counts, excluding: []), [])
    }

    func testChipsShowTheListThenBodyTagsInText() {
        let bud = Bud(text: "Apartment hunt", body: "Ask about noise #neighbourhood and #Home", tags: ["home", "lisbon"])
        XCTAssertEqual(bud.tagChips, [
            TagChip(tag: "home", inText: false), TagChip(tag: "lisbon", inText: false), TagChip(tag: "neighbourhood", inText: true),
        ])
    }
}
