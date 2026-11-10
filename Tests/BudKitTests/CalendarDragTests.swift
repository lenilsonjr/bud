import XCTest
@testable import BudKit

/// A day dragged on the calendar: the pure moves the grid draws while an end is in hand, and
/// the cell a point lands in.
final class CalendarDragTests: XCTestCase {
    /// A Monday-first calendar in UTC, so every day lands where the board draws it.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_GB")
        c.firstWeekday = 2
        return c
    }

    private let day: TimeInterval = 86_400
    private var now: Date { Tree.stillNow }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute))!
    }

    func testMovingADayKeepsItsTimeOfDay() {
        let morning = date(2026, 11, 3, 9, 30)
        XCTAssertEqual(DateField.when.moved(morning, toDay: date(2026, 11, 14), calendar: calendar), date(2026, 11, 14, 9, 30))
        XCTAssertEqual(DateField.due.moved(morning, toDay: date(2026, 10, 30, 23, 59), calendar: calendar), date(2026, 10, 30, 9, 30), "Back in time too, and only the day of the target counts")
        XCTAssertEqual(DateField.when.moved(morning, toDay: date(2026, 11, 3, 18), calendar: calendar), morning, "The same day moves nothing")
    }

    func testAnEntryMovedKeepsItsOtherDay() throws {
        let entries = CalendarEntry.all(in: CalendarMonthTests.world(), calendar: calendar)
        let issue = try XCTUnwrap(entries.first { $0.title == "Send the first issue" })
        let dueMoved = issue.moved(.due, toDay: date(2026, 11, 27, 15), calendar: calendar)
        XCTAssertEqual(dueMoved.due, date(2026, 11, 27), "At midnight, as the grid holds its days")
        XCTAssertEqual(dueMoved.when, issue.when)
        let whenMoved = issue.moved(.when, toDay: date(2026, 11, 2), calendar: calendar)
        XCTAssertEqual(whenMoved.when, date(2026, 11, 2))
        XCTAssertEqual(whenMoved.due, issue.due)
        XCTAssertEqual(whenMoved.id, issue.id)
        XCTAssertEqual(whenMoved.tone, issue.tone)
        XCTAssertEqual(issue.day(.when), issue.when)
        XCTAssertEqual(issue.day(.due), issue.due)
    }

    func testTheDayUnderAPointIsItsCell() {
        let month = CalendarMonth(containing: now, now: now, calendar: calendar)
        let size = CGSize(width: 700, height: 600)
        XCTAssertEqual(month.day(under: CGPoint(x: 150, y: 250), in: size), month.weeks[2][1].date)
        XCTAssertEqual(month.day(under: CGPoint(x: 0, y: 0), in: size), month.gridStart)
        XCTAssertEqual(month.day(under: CGPoint(x: 699, y: 599), in: size), month.weeks[5][6].date)
        XCTAssertNil(month.day(under: CGPoint(x: -1, y: 10), in: size))
        XCTAssertNil(month.day(under: CGPoint(x: 10, y: 600), in: size))
        XCTAssertNil(month.day(under: CGPoint(x: 10, y: 10), in: .zero))
    }

    func testMovingTheDueEndStretchesTheBarToTheDayUnderThePointer() throws {
        let month = CalendarMonth(containing: now, now: now, calendar: calendar)
        let entries = CalendarEntry.all(in: CalendarMonthTests.world(), calendar: calendar)
        let issue = try XCTUnwrap(entries.first { $0.title == "Send the first issue" })
        let still = MonthGrid(month: month, entries: entries, state: CalendarState())
        XCTAssertEqual(still.bars.filter { $0.entry == issue.id }.map(\.row), [1, 2, 3, 4], "Friday 6 to Monday 23, under the week of 26 October")
        // The due end over Friday 27: the bar reaches the end of that week's row.
        let drag = CalendarDrag(entry: issue.id, field: .due, point: CGPoint(x: 800, y: 420), over: date(2026, 11, 27))
        let moving = MonthGrid(month: month, entries: entries.moving(drag, calendar: calendar), state: CalendarState())
        let pieces = moving.bars.filter { $0.entry == issue.id }
        XCTAssertEqual(pieces.map(\.row), [1, 2, 3, 4])
        XCTAssertEqual(pieces.last?.to, 4, "Friday")
        XCTAssertEqual(pieces.last?.dueLabel, "due 27 Nov")
        XCTAssertEqual(pieces.first?.from, 4, "The when end stays on Friday 6")
        XCTAssertTrue(pieces.first?.starts ?? false)
        // The when end over Monday 2: the bar starts a cell earlier and keeps its due day.
        let earlier = CalendarDrag(entry: issue.id, field: .when, point: .zero, over: date(2026, 11, 2))
        let first = MonthGrid(month: month, entries: entries.moving(earlier, calendar: calendar), state: CalendarState()).bars.first { $0.entry == issue.id }
        XCTAssertEqual(first?.from, 0)
        XCTAssertEqual(moving.bars.filter { $0.entry != issue.id }, still.bars.filter { $0.entry != issue.id }, "No other bar moves")
    }

    func testADragOffTheGridMovesNothing() throws {
        let entries = CalendarEntry.all(in: CalendarMonthTests.world(), calendar: calendar)
        let issue = try XCTUnwrap(entries.first { $0.title == "Send the first issue" })
        let off = CalendarDrag(entry: issue.id, field: .due, point: CGPoint(x: -20, y: 0), over: nil)
        XCTAssertEqual(entries.moving(off, calendar: calendar), entries)
        XCTAssertEqual(entries.moving(nil, calendar: calendar), entries)
    }

    func testAFieldDrawsWithItsSymbol() {
        XCTAssertEqual(DateField.when.symbol, "arrow.right")
        XCTAssertEqual(DateField.due.symbol, "flag")
        XCTAssertEqual(DateField.allCases.map(\.rawValue), ["when", "due"], "The front matter keys")
    }

    func testADayLabelReadsTheSameEverywhere() {
        XCTAssertEqual(DayText.day(date(2026, 11, 27), calendar: calendar), "27 Nov")
        XCTAssertEqual(DayText.day(date(2026, 12, 4), calendar: calendar), "4 Dec")
    }
}

#if canImport(SwiftUI)
/// The store's one step for a drag: the day written to the file, nothing else changed, and the
/// toast whose Undo puts it back.
@MainActor
final class CalendarDragStoreTests: XCTestCase {
    private func loaded() async -> (BudStore, MemoryVault) {
        let vault = MemoryVault(tree: Tree.seed())
        let store = BudStore(vault: vault)
        await store.reload()
        return (store, vault)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute))!
    }

    /// Waits for an undo, which runs on its own task, to reach the tree and the vault.
    private func settled(_ store: BudStore, until done: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 where !done() { await Task.yield() }
        await store.settle()
    }

    func testDraggingABarsEndWritesOnlyThatDayAndUndoPutsItBack() async throws {
        let (store, vault) = await loaded()
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first)
        let issue = try XCTUnwrap(store.add("Send the first issue", todo: true, under: thread.id))
        store.setWhen(issue.id, date(2026, 11, 6, 9, 30))
        store.setDue(issue.id, date(2026, 11, 23, 17))
        store.setBody(issue.id, "Three stories and a note from the editor.")
        store.addTag(issue.id, "launch")
        await store.settle()
        let before = try await vault.text(issue.id.uuidString)
        XCTAssertTrue(before.contains("when: 2026-11-06\n"), before)
        XCTAssertTrue(before.contains("due: 2026-11-23\n"), before)

        store.moveDate(.due, of: issue.id, to: date(2026, 11, 27))
        await store.settle()
        let after = try await vault.text(issue.id.uuidString)
        XCTAssertEqual(after, before.replacingOccurrences(of: "due: 2026-11-23\n", with: "due: 2026-11-27\n"), "Only the due key changes")
        XCTAssertEqual(store.tree.bud(issue.id)?.due, date(2026, 11, 27, 17), "The time of day stays")
        XCTAssertEqual(store.tree.bud(issue.id)?.when, date(2026, 11, 6, 9, 30))
        XCTAssertEqual(store.toasts.current?.action.message, "Made Send the first issue due 27 Nov")
        XCTAssertEqual(store.toasts.current?.action.systemImage, "flag")

        store.toasts.undo()
        await settled(store) { store.tree.bud(issue.id)?.due == self.date(2026, 11, 23, 17) }
        XCTAssertEqual(store.tree.bud(issue.id)?.due, date(2026, 11, 23, 17))
        let restored = try await vault.text(issue.id.uuidString)
        XCTAssertEqual(restored, before)
        XCTAssertNil(store.toasts.current, "Undo takes the toast with it")

        store.moveWhen(of: issue.id, to: date(2026, 11, 2, 23))
        await store.settle()
        let earlier = try await vault.text(issue.id.uuidString)
        XCTAssertEqual(earlier, before.replacingOccurrences(of: "when: 2026-11-06\n", with: "when: 2026-11-02\n"), "Only the when key changes")
        XCTAssertEqual(store.tree.bud(issue.id)?.when, date(2026, 11, 2, 9, 30))
        XCTAssertEqual(store.toasts.current?.action.message, "Scheduled Send the first issue for 2 Nov")
        XCTAssertEqual(store.toasts.current?.action.systemImage, "calendar")
    }

    func testDraggingAnItemMovesItsOneDay() async throws {
        let (store, vault) = await loaded()
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first)
        let walk = try XCTUnwrap(store.add("A walk before the first meeting", todo: false, under: thread.id))
        store.setWhen(walk.id, date(2026, 11, 3, 7))
        await store.settle()
        let before = try await vault.text(walk.id.uuidString)
        XCTAssertEqual(before, "---\nwhen: 2026-11-03\n---\n")

        store.moveWhen(of: walk.id, to: date(2026, 11, 14))
        await store.settle()
        let moved = try await vault.text(walk.id.uuidString)
        XCTAssertEqual(moved, "---\nwhen: 2026-11-14\n---\n", "The one day moves and no due appears")
        XCTAssertEqual(store.tree.bud(walk.id)?.when, date(2026, 11, 14, 7))
        XCTAssertNil(store.tree.bud(walk.id)?.due)
        XCTAssertEqual(store.toasts.current?.action.message, "Scheduled A walk before the first meeting for 14 Nov")

        store.toasts.undo()
        await settled(store) { store.tree.bud(walk.id)?.when == self.date(2026, 11, 3, 7) }
        let restored = try await vault.text(walk.id.uuidString)
        XCTAssertEqual(restored, before)

        store.moveDue(of: walk.id, to: date(2026, 11, 20))
        await store.settle()
        let unchanged = try await vault.text(walk.id.uuidString)
        XCTAssertEqual(unchanged, before, "A day the bud does not have cannot be dragged")
    }

    func testADropOnTheSameDayChangesNothingAndSaysNothing() async throws {
        let (store, vault) = await loaded()
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first)
        let issue = try XCTUnwrap(store.add("Send the first issue", todo: true, under: thread.id))
        store.setDue(issue.id, date(2026, 11, 23, 17))
        await store.settle()
        let before = try await vault.text(issue.id.uuidString)
        store.toasts.dismiss()
        store.moveDue(of: issue.id, to: date(2026, 11, 23, 8))
        await store.settle()
        let unchanged = try await vault.text(issue.id.uuidString)
        XCTAssertEqual(unchanged, before)
        XCTAssertEqual(store.tree.bud(issue.id)?.due, date(2026, 11, 23, 17))
        XCTAssertNil(store.toasts.current)
    }

    func testTheMonthDrawsTheBudWhereADragWouldDropIt() throws {
        let clock: @Sendable () -> Date = { Tree.stillNow }
        let devices = DeviceStore(peers: MemoryPeers(now: clock), now: clock)
        let fixed = BudStore(fileURL: nil, devices: devices)
        defer { fixed.calendarState = CalendarState() }
        let thread = try XCTUnwrap(fixed.tree.children(of: rootID).first)
        let issue = try XCTUnwrap(fixed.add("Send the first issue", todo: true, under: thread.id))
        let day: TimeInterval = 86_400
        fixed.setWhen(issue.id, fixed.now.addingTimeInterval(3 * day))
        fixed.setDue(issue.id, fixed.now.addingTimeInterval(20 * day))
        fixed.calendarState = CalendarState()
        let still = fixed.monthGrid.bars.filter { $0.entry == issue.id }
        let drag = CalendarDrag(entry: issue.id, field: .due, point: .zero, over: fixed.now.addingTimeInterval(27 * day))
        let moving = fixed.monthGrid(moving: drag).bars.filter { $0.entry == issue.id }
        XCTAssertEqual(moving.count, still.count + 1, "One more week's row")
        XCTAssertEqual(fixed.monthGrid(moving: nil), fixed.monthGrid)
        XCTAssertEqual(fixed.tree.bud(issue.id)?.due, fixed.now.addingTimeInterval(20 * day), "A preview writes nothing")
    }
}
#endif
