import XCTest
@testable import BudKit

/// A day dragged on the calendar: the pure moves the grid draws while an end is in hand, the
/// end of a piece each day sits at, and the cell a point lands in.
final class CalendarDragTests: XCTestCase {
    /// A Monday-first calendar in UTC, so every day lands where the board draws it.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_GB")
        c.firstWeekday = 2
        return c
    }

    private var now: Date { Tree.stillNow }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute))!
    }

    private var month: CalendarMonth { CalendarMonth(containing: now, now: now, calendar: calendar) }
    /// Built once a test: the world gives the issue a fresh id each time it is made.
    private lazy var entries: [CalendarEntry] = CalendarEntry.all(in: CalendarMonthTests.world(), calendar: calendar)
    private func issue(in entries: [CalendarEntry]) throws -> CalendarEntry {
        try XCTUnwrap(entries.first { $0.title == "Send the first issue" })
    }

    func testMovingADayKeepsItsTimeOfDay() {
        let morning = date(2026, 11, 3, 9, 30)
        XCTAssertEqual(DateKey.when.moved(morning, toDay: date(2026, 11, 14), calendar: calendar), date(2026, 11, 14, 9, 30))
        XCTAssertEqual(DateKey.due.moved(morning, toDay: date(2026, 10, 30, 23, 59), calendar: calendar), date(2026, 10, 30, 9, 30), "Back in time too, and only the day of the target counts")
        XCTAssertEqual(DateKey.when.moved(morning, toDay: date(2026, 11, 3, 18), calendar: calendar), morning, "The same day moves nothing")
    }

    func testAnEntryMovedKeepsItsOtherDay() throws {
        let issue = try issue(in: entries)
        let dueMoved = issue.moved(.due, toDay: date(2026, 11, 27, 15), calendar: calendar)
        XCTAssertEqual(dueMoved.due, date(2026, 11, 27), "At midnight, as the grid holds its days")
        XCTAssertEqual(dueMoved.when, issue.when)
        let whenMoved = issue.moved(.when, toDay: date(2026, 11, 2), calendar: calendar)
        XCTAssertEqual(whenMoved.when, date(2026, 11, 2))
        XCTAssertEqual(whenMoved.due, issue.due)
        XCTAssertEqual(whenMoved.id, issue.id)
        XCTAssertEqual(whenMoved.tone, issue.tone)
    }

    func testTheDayUnderAPointIsItsCell() {
        let size = CGSize(width: 700, height: 600)
        XCTAssertEqual(month.day(under: CGPoint(x: 150, y: 250), in: size), month.weeks[2][1].date)
        XCTAssertEqual(month.day(under: CGPoint(x: 0, y: 0), in: size), month.gridStart)
        XCTAssertEqual(month.day(under: CGPoint(x: 699, y: 599), in: size), month.weeks[5][6].date)
        XCTAssertNil(month.day(under: CGPoint(x: -1, y: 10), in: size))
        XCTAssertNil(month.day(under: CGPoint(x: 10, y: 600), in: size))
        XCTAssertNil(month.day(under: CGPoint(x: 10, y: 10), in: .zero))
    }

    func testEachDaySitsAtOneEndOfOnePieceAndTheWeeksEdgesDragNothing() throws {
        let grid = MonthGrid(month: month, entries: entries, state: CalendarState())
        let pieces = grid.bars.filter { $0.title == "Send the first issue" }
        XCTAssertEqual(pieces.map(\.row), [1, 2, 3, 4], "Friday 6 to Monday 23, under the week of 26 October")
        XCTAssertEqual(pieces.map(\.whenEnd), [.leading, nil, nil, nil])
        XCTAssertEqual(pieces.map(\.dueEnd), [nil, nil, nil, .trailing])
        XCTAssertEqual(pieces[0].key(at: .leading), .when)
        XCTAssertNil(pieces[0].key(at: .trailing), "The end of the week, not a day of the bud")
        XCTAssertNil(pieces[1].key(at: .leading))
        XCTAssertNil(pieces[1].key(at: .trailing))
        XCTAssertNil(pieces[3].key(at: .leading))
        XCTAssertEqual(pieces[3].key(at: .trailing), .due)
        // Both days in one week: the arrow leads and the flag ends the one piece.
        let onboarding = grid.bars.filter { $0.title == "Review the onboarding flow" }
        XCTAssertEqual(onboarding.map(\.whenEnd), [.leading, nil])
        XCTAssertEqual(onboarding.map(\.dueEnd), [nil, .trailing])
    }

    func testADueBeforeItsWhenSitsAtTheLeadingEnd() throws {
        var tree = Tree()
        let thread = tree.add("Launch", todo: false, under: rootID)
        let late = tree.add("Late start", todo: true, under: thread.id)
        tree.setWhen(late.id, date(2026, 11, 20))
        tree.setDue(late.id, date(2026, 11, 10))
        let grid = MonthGrid(month: month, entries: CalendarEntry.all(in: tree, calendar: calendar), state: CalendarState())
        let pieces = grid.bars.filter { $0.entry == late.id }
        XCTAssertEqual(pieces.map(\.row), [2, 3], "Tuesday 10 to Friday 20")
        XCTAssertEqual(pieces.first?.key(at: .leading), .due, "The flag leads")
        XCTAssertNil(pieces.first?.key(at: .trailing))
        XCTAssertEqual(pieces.last?.key(at: .trailing), .when, "The arrow ends")
        XCTAssertNil(pieces.last?.key(at: .leading))
    }

    func testMovingTheDueEndStretchesTheBarToTheDayUnderThePointer() throws {
        let issue = try issue(in: entries)
        let still = MonthGrid(month: month, entries: entries, state: CalendarState())
        // The due end over Friday 27: the bar reaches the end of that week's row.
        let drag = CalendarDrag(entry: issue.id, key: .due, point: CGPoint(x: 800, y: 420), over: date(2026, 11, 27))
        let moving = still.moving(drag)
        let pieces = moving.bars.filter { $0.entry == issue.id }
        XCTAssertEqual(pieces.map(\.row), [1, 2, 3, 4])
        XCTAssertEqual(pieces.last?.to, 4, "Friday")
        XCTAssertEqual(pieces.last?.dueLabel, "due 27 Nov")
        XCTAssertEqual(pieces.last?.dueEnd, .trailing)
        XCTAssertEqual(pieces.first?.from, 4, "The when end stays on Friday 6")
        XCTAssertTrue(pieces.first?.starts ?? false)
        XCTAssertEqual(moving.month, still.month)
        XCTAssertEqual(moving.state, still.state)
        XCTAssertEqual(moving.bars.filter { $0.entry != issue.id }, still.bars.filter { $0.entry != issue.id }, "No other bar moves")
        // The when end over Monday 2: the bar starts a cell earlier and keeps its due day.
        let earlier = CalendarDrag(entry: issue.id, key: .when, point: .zero, over: date(2026, 11, 2))
        let first = still.moving(earlier).bars.first { $0.entry == issue.id }
        XCTAssertEqual(first?.from, 0)
        XCTAssertEqual(first?.row, 1)
        // The when end onto the due day: an item with the flag, no bar.
        let together = CalendarDrag(entry: issue.id, key: .when, point: .zero, over: date(2026, 11, 23, 11))
        let joined = still.moving(together)
        XCTAssertTrue(joined.bars.filter { $0.entry == issue.id }.isEmpty)
        let item = joined.items.first { $0.entry == issue.id }
        XCTAssertEqual(item?.row, 4)
        XCTAssertEqual(item?.column, 0, "Monday 23")
        XCTAssertEqual(item?.isDue, true, "The due day wins the flag")
    }

    func testADragOffTheGridMovesNothing() throws {
        let issue = try issue(in: entries)
        let still = MonthGrid(month: month, entries: entries, state: CalendarState())
        let off = CalendarDrag(entry: issue.id, key: .due, point: CGPoint(x: -20, y: 0), over: nil)
        XCTAssertEqual(entries.moving(off, calendar: calendar), entries)
        XCTAssertEqual(entries.moving(nil, calendar: calendar), entries)
        XCTAssertEqual(still.moving(off), still, "Nothing is rebuilt while the pointer is off the grid")
    }

    func testAKeyDrawsWithItsSymbol() {
        XCTAssertEqual(DateKey.when.symbol, "arrow.right")
        XCTAssertEqual(DateKey.due.symbol, "flag")
        XCTAssertEqual(DateKey.allCases.map(\.rawValue), ["when", "due"], "The front matter keys")
    }
}

#if canImport(SwiftUI)
/// The store's one step for a drag: the day written to the file, nothing else changed, and the
/// toast whose Undo puts it back.
@MainActor
final class CalendarDragStoreTests: XCTestCase {
    /// The device's own calendar with the board's locale, so the toast's day reads "27 Nov".
    private var calendar: Calendar {
        var c = Calendar.current
        c.locale = Locale(identifier: "en_GB")
        return c
    }

    private func loaded(_ tree: Tree = Tree.seed()) async -> (BudStore, MemoryVault) {
        let vault = MemoryVault(tree: tree)
        let store = BudStore(vault: vault, devices: DeviceStore(peers: MemoryPeers(now: { Date() }), calendar: calendar))
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
        let restored = try await vault.text(issue.id.uuidString)
        XCTAssertEqual(restored, before)
        XCTAssertNil(store.toasts.current, "Undo takes the toast with it")

        store.moveDate(.when, of: issue.id, to: date(2026, 11, 2, 23))
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

        store.moveDate(.when, of: walk.id, to: date(2026, 11, 14))
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

        store.moveDate(.due, of: walk.id, to: date(2026, 11, 20))
        await store.settle()
        let unchanged = try await vault.text(walk.id.uuidString)
        XCTAssertEqual(unchanged, before, "A day the bud does not have cannot be dragged")
    }

    func testDraggingARoutineOffItsStampedDayGivesItAWhenAndUndoTakesItAway() async throws {
        var tree = Tree.seed()
        let thread = try XCTUnwrap(tree.children(of: rootID).first)
        let key = Tree.stampKey("Weekly review", at: date(2026, 11, 16, 9))
        tree.plant("Weekly review", todo: true, under: thread.id, from: key)
        let (store, vault) = await loaded(tree)
        let review = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.from == key })
        XCTAssertNil(review.when, "Shown on its stamped day, with no when of its own")
        let before = try await vault.text(review.id.uuidString)
        XCTAssertFalse(before.contains("when:"), before)

        store.moveDate(.when, of: review.id, to: date(2026, 11, 18))
        await store.settle()
        let given = try await vault.text(review.id.uuidString)
        XCTAssertTrue(given.contains("when: 2026-11-18\n"), given)
        XCTAssertEqual(given.replacingOccurrences(of: "when: 2026-11-18\n", with: ""), before, "The when key alone is added")
        XCTAssertEqual(store.tree.bud(review.id)?.when, date(2026, 11, 18, 9), "Two days on from the stamp, at its time")
        XCTAssertEqual(store.toasts.current?.action.message, "Scheduled Weekly review for 18 Nov")

        store.toasts.undo()
        await settled(store) { store.tree.bud(review.id)?.when == nil }
        let restored = try await vault.text(review.id.uuidString)
        XCTAssertEqual(restored, before, "Back on its stamped day with no when")
    }

    func testADropOnTheSameDayChangesNothingAndSaysNothing() async throws {
        let (store, vault) = await loaded()
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first)
        let issue = try XCTUnwrap(store.add("Send the first issue", todo: true, under: thread.id))
        store.setDue(issue.id, date(2026, 11, 23, 17))
        await store.settle()
        let before = try await vault.text(issue.id.uuidString)
        store.toasts.dismiss()
        store.moveDate(.due, of: issue.id, to: date(2026, 11, 23, 8))
        await store.settle()
        let unchanged = try await vault.text(issue.id.uuidString)
        XCTAssertEqual(unchanged, before)
        XCTAssertEqual(store.tree.bud(issue.id)?.due, date(2026, 11, 23, 17))
        XCTAssertNil(store.toasts.current)
    }

    func testTheMonthDrawsTheBudWhereADragWouldDropItAndWritesNothing() throws {
        let clock: @Sendable () -> Date = { Tree.stillNow }
        let devices = DeviceStore(peers: MemoryPeers(now: clock), now: clock)
        let fixed = BudStore(fileURL: nil, devices: devices)
        defer { fixed.calendarState = CalendarState() }
        let thread = try XCTUnwrap(fixed.tree.children(of: rootID).first)
        let issue = try XCTUnwrap(fixed.add("Send the first issue", todo: true, under: thread.id))
        let day: TimeInterval = 86_400
        let due = fixed.now.addingTimeInterval(20 * day)
        fixed.setWhen(issue.id, fixed.now.addingTimeInterval(3 * day))
        fixed.setDue(issue.id, due)
        fixed.calendarState = CalendarState()
        let grid = fixed.monthGrid
        let still = grid.bars.filter { $0.entry == issue.id }
        let drag = CalendarDrag(entry: issue.id, key: .due, point: .zero, over: fixed.now.addingTimeInterval(27 * day))
        let moving = grid.moving(drag).bars.filter { $0.entry == issue.id }
        XCTAssertEqual(moving.count, still.count + 1, "One more week's row")
        XCTAssertEqual(fixed.monthGrid.bars.filter { $0.entry == issue.id }, still, "The grid itself is as it was")
        XCTAssertEqual(fixed.tree.bud(issue.id)?.due, due, "A preview writes nothing")
        XCTAssertNil(fixed.toasts.current)
    }
}
#endif
