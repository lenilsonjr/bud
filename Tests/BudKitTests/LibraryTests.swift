import XCTest
@testable import BudKit

final class LibraryTests: XCTestCase {
    private func treeWithTemplate() -> (Tree, Bud) {
        var tree = Tree.seed()
        let template = tree.add("Weekly review", todo: true, under: warehouseID)
        tree.add("Clear the inbox", todo: true, under: template.id)
        tree.add("Plan the week", todo: true, under: template.id)
        return (tree, template)
    }

    func testATemplateLivesInTheWarehouseAndStaysOutOfTheLenses() {
        let (tree, template) = treeWithTemplate()
        XCTAssertEqual(tree.templates().map(\.text), ["Weekly review"])
        XCTAssertEqual(tree.place(of: template.id), .warehouse)
        XCTAssertEqual(tree.place(of: tree.children(of: template.id)[0].id), .warehouse)
        XCTAssertEqual(tree.title(of: warehouseID), "Warehouse")
        XCTAssertNil(tree.parent(of: warehouseID))
        let open = tree.walk(under: rootID).filter { $0.state == .open }.map(\.text)
        XCTAssertFalse(open.contains("Clear the inbox"), "a template's to-dos are not yours until stamped")
        XCTAssertFalse(tree.today(on: .distantFuture).due.contains { $0.text == "Weekly review" })
    }

    func testTheWarehouseSurvivesARoundTripThroughRecords() {
        let (tree, _) = treeWithTemplate()
        let records = tree.records()
        let top = records.first { $0.title == "Weekly review" }
        XCTAssertEqual(top?.place, .warehouse)
        XCTAssertEqual(top?.parent, warehouseID.uuidString, "as the Inbox names itself, the Warehouse does")
        let again = Tree(records: records)
        XCTAssertEqual(again.templates().map(\.text), ["Weekly review"])
        XCTAssertEqual(again.children(of: again.templates()[0].id).map(\.text), ["Clear the inbox", "Plan the week"])
    }

    func testAStampKeyNamesTheTemplateAndTheMinute() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 9, minute: 0))!
        XCTAssertEqual(Tree.stampKey("Weekly review", at: date), "tpl/Weekly review/2026-11-09T14:00Z", "the same on every device")
    }

    func testTheWarehouseWords() {
        XCTAssertEqual(WarehouseText.count(1), "1 template")
        XCTAssertEqual(WarehouseText.caption(buds: 3), "Template · 3 buds")
        XCTAssertEqual(WarehouseText.caption(buds: 3, triggers: 1), "Template · 3 buds · used by 1 trigger")
    }
}
