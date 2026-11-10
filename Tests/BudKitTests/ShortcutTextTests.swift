import XCTest
@testable import BudKit

final class ShortcutTextTests: XCTestCase {
    func testTheSheetsWords() {
        XCTAssertEqual(ShortcutText.title, "Keyboard shortcuts")
        XCTAssertEqual(ShortcutText.note, "Every key the app answers to.")
        XCTAssertEqual(ShortcutText.systemWideTitle, "From any app")
        XCTAssertEqual(ShortcutText.systemWideCaption, "On the Mac, with any app in front.")
        XCTAssertEqual(Command.Scope.allCases.map(ShortcutText.groupTitle), ["Everywhere", "On the canvas", "In Files", "On a page"])
    }

    func testTheSystemWideKeysComeLastInTheirOwnGroupMarkedMac() throws {
        let groups = ShortcutText.groups()
        let last = try XCTUnwrap(groups.last)
        XCTAssertEqual(last.title, ShortcutText.systemWideTitle)
        XCTAssertEqual(last.caption, ShortcutText.systemWideCaption)
        XCTAssertEqual(last.commands.map(\.id), [.capture])
        XCTAssertEqual(groups.dropLast().map(\.title), ["Everywhere", "On the canvas", "On a page"], "Files has no rows yet, so no group")
        XCTAssertTrue(groups.dropLast().allSatisfy { $0.caption == nil })
    }

    func testEveryRowOfTheTableIsOnTheSheetOnce() {
        let listed = ShortcutText.groups().flatMap(\.commands).map(\.id)
        XCTAssertEqual(listed.count, Set(listed).count)
        XCTAssertEqual(Set(listed), Set(Command.ID.allCases))
        XCTAssertEqual(ShortcutText.groups()[0].commands.map(\.id).first, .goAnywhere)
        XCTAssertFalse(ShortcutText.groups()[0].commands.map(\.id).contains(.capture), "A system-wide key is listed in its group alone")
    }

    func testTheHalvesSplitWholeGroupsAroundTheMiddle() {
        let groups = ShortcutText.groups()
        let (left, right) = ShortcutText.halves(groups)
        XCTAssertEqual(left + right, groups)
        XCTAssertEqual(left.map(\.title), ["Everywhere"])
        XCTAssertEqual(right.map(\.title), ["On the canvas", "On a page", ShortcutText.systemWideTitle])
        let one = [ShortcutText.Group(title: "A", caption: nil, commands: [Command.of(.undo)])]
        XCTAssertEqual(ShortcutText.halves(one).0, one)
        XCTAssertEqual(ShortcutText.halves(one).1, [])
        XCTAssertEqual(ShortcutText.halves([]).0, [])
    }
}
