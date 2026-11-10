import XCTest
@testable import BudKit

/// The calendar's pure model: the month's days, the threads and their colours, the bars and
/// items placed on the grid, and what the threads and Show switches hide.
final class CalendarMonthTests: XCTestCase {
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

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// The seed world with two buds that are scheduled and due, so the month has bars across its
    /// weeks: one under the newsletter, Friday 6 to Monday 23; one under the roadmap, Wednesday
    /// 4 to Saturday 14.
    static func world(now: Date = Tree.stillNow) -> Tree {
        var tree = Tree.seed(now: now)
        let day: TimeInterval = 86_400
        let newsletter = tree.children(of: rootID).first { $0.text == "Launch the newsletter" }!
        let issue = tree.add("Send the first issue", todo: true, under: newsletter.id)
        tree.setWhen(issue.id, now.addingTimeInterval(3 * day))
        tree.setDue(issue.id, now.addingTimeInterval(20 * day))
        let onboarding = tree.walk(under: rootID).first { $0.text == "Review the onboarding flow" }!
        tree.setWhen(onboarding.id, now.addingTimeInterval(1 * day))
        tree.setDue(onboarding.id, now.addingTimeInterval(11 * day))
        return tree
    }

    // MARK: The month

    func testTheStillMomentIsATuesdayMorningInNovember2026() {
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day, .hour, .weekday], from: Tree.stillNow), DateComponents(year: 2026, month: 11, day: 3, hour: 10, weekday: 3))
    }

    func testTheMonthIsSixRowsOfSevenFromTheWeekItStartsIn() {
        let month = CalendarMonth(containing: now, now: now, calendar: calendar)
        XCTAssertEqual(month.title, "November 2026")
        XCTAssertEqual(month.weekdays, ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"])
        XCTAssertEqual(month.weeks.count, 6)
        XCTAssertEqual(month.weeks.map(\.count), Array(repeating: 7, count: 6))
        XCTAssertEqual(month.weeks[0].map(\.number), [26, 27, 28, 29, 30, 31, 1], "October's last days fill the first row")
        XCTAssertEqual(month.weeks[0].map(\.inMonth), [false, false, false, false, false, false, true])
        XCTAssertEqual(month.weeks[5].map(\.number), [30, 1, 2, 3, 4, 5, 6], "December's first days fill the last")
        XCTAssertEqual(month.weeks[5].map(\.inMonth), [true, false, false, false, false, false, false])
        XCTAssertEqual(month.weeks[1][1].number, 3)
        XCTAssertTrue(month.weeks[1][1].isToday)
        XCTAssertEqual(month.weeks.flatMap { $0 }.filter(\.isToday).count, 1, "One today")
        XCTAssertEqual(month.weeks[1].map(\.isWeekend), [false, false, false, false, false, true, true])
        XCTAssertEqual(month.gridStart, date(2026, 10, 26))
        XCTAssertEqual(month.gridEnd, date(2026, 12, 7))
    }

    func testAMonthStartingOnTheFirstWeekdayStillShowsSixRows() {
        var sunday = calendar
        sunday.firstWeekday = 1
        let month = CalendarMonth(containing: date(2026, 11, 1), now: now, calendar: sunday)
        XCTAssertEqual(month.weeks[0][0].number, 1, "November 2026 starts on a Sunday")
        XCTAssertEqual(month.weekdays.first, "SUN")
        XCTAssertEqual(month.weeks.count, 6)
        XCTAssertEqual(month.weeks[5].map(\.inMonth), Array(repeating: false, count: 7))
    }

    func testACellIsFoundForEveryDayInTheGridAndForNoneOutside() {
        let month = CalendarMonth(containing: now, now: now, calendar: calendar)
        XCTAssertEqual(month.cell(of: date(2026, 10, 26))?.row, 0)
        XCTAssertEqual(month.cell(of: date(2026, 10, 26))?.column, 0)
        XCTAssertEqual(month.cell(of: now)?.row, 1, "Today, with its hour, lands on its day")
        XCTAssertEqual(month.cell(of: now)?.column, 1)
        XCTAssertEqual(month.cell(of: date(2026, 12, 6))?.row, 5)
        XCTAssertEqual(month.cell(of: date(2026, 12, 6))?.column, 6)
        XCTAssertNil(month.cell(of: date(2026, 12, 7)))
        XCTAssertNil(month.cell(of: date(2026, 10, 25)))
    }

    func testShiftingMovesAMonthAndKeepsToday() {
        let month = CalendarMonth(containing: now, now: now, calendar: calendar)
        let next = month.shifted(by: 1, now: now)
        XCTAssertEqual(next.title, "December 2026")
        XCTAssertEqual(next.start, date(2026, 12, 1))
        XCTAssertFalse(next.weeks.flatMap { $0 }.contains(where: \.isToday), "Today is not in December")
        XCTAssertEqual(month.shifted(by: -1, now: now).title, "October 2026")
        XCTAssertEqual(month.shifted(by: 2, now: now).shifted(by: -2, now: now), month)
    }

    func testTheRangeTitlesReadAsTheBoardWritesThem() {
        XCTAssertEqual(CalendarRange.month.title(for: now, calendar: calendar), "November 2026")
        XCTAssertEqual(CalendarRange.quarter.title(for: now, calendar: calendar), "Q4 2026")
        XCTAssertEqual(CalendarRange.year.title(for: now, calendar: calendar), "2026")
        XCTAssertEqual(CalendarRange.day.title(for: now, calendar: calendar), "Tuesday, 3 November 2026")
        XCTAssertEqual(CalendarRange.week.title(for: now, calendar: calendar), "2 Nov – 8 Nov 2026")
        XCTAssertEqual(CalendarRange.custom.title(for: now, calendar: calendar), "November 2026")
    }

    func testTheSegmentsAndSwitchesAreTheBoardsInItsOrder() {
        XCTAssertEqual(CalendarRange.allCases.map(\.rawValue), ["Day", "Week", "Month", "Quarter", "Year", "Custom"])
        XCTAssertEqual(CalendarLayout.allCases.map(\.rawValue), ["Calendar", "Timeline"])
        XCTAssertEqual(CalendarShow.allCases.map(\.rawValue), ["When", "Due", "Routines", "Done"])
        XCTAssertEqual(CalendarRange.week.comingLine, "The week view is coming.")
        XCTAssertEqual(CalendarRange.custom.comingLine, "The custom range is coming.")
        XCTAssertEqual(CalendarLayout.timeline.comingLine, "The timeline is coming.")
    }

    // MARK: Threads

    func testEveryTopLevelBranchIsAThreadColouredInTurn() {
        let tree = Self.world()
        let threads = CalendarThread.list(in: tree)
        XCTAssertEqual(threads.map(\.title), tree.children(of: rootID).map(\.text))
        XCTAssertEqual(threads.prefix(4).map(\.tone), [.leaf, .amethyst, .pistil, .rose], "The four accents, as the board colours its threads")
        XCTAssertEqual(threads[4].tone, .leaf, "Then round again")
        XCTAssertEqual(ThreadTone.at(-1), .rose)
        for tone in ThreadTone.allCases {
            XCTAssertNotEqual(tone.tone, tone.soft, "\(tone) has a strong and a soft tone")
        }
        XCTAssertEqual(ThreadTone.leaf.tone, Palette.leaf)
        XCTAssertEqual(ThreadTone.rose.soft, Palette.roseSoft)
    }

    func testAnEntryCarriesItsThreadAndItsDaysAtMidnight() throws {
        let tree = Self.world()
        let entries = CalendarEntry.all(in: tree, calendar: calendar)
        let walk = try XCTUnwrap(entries.first { $0.title == "A walk before the first meeting" })
        let health = try XCTUnwrap(tree.children(of: rootID).first { $0.text == "Health reset" })
        XCTAssertEqual(walk.thread, health.id)
        XCTAssertEqual(walk.tone, .rose)
        XCTAssertEqual(walk.when, date(2026, 11, 3), "Ten in the morning becomes the day")
        XCTAssertNil(walk.due)
        let issue = try XCTUnwrap(entries.first { $0.title == "Send the first issue" })
        XCTAssertEqual(issue.when, date(2026, 11, 6))
        XCTAssertEqual(issue.due, date(2026, 11, 23))
        XCTAssertEqual(issue.tone, .leaf)
        XCTAssertFalse(entries.contains { $0.title == "Launch the newsletter" }, "No date, no entry")
        XCTAssertFalse(entries.contains { $0.title.hasPrefix("Ask the printer") }, "The Inbox is not under a thread")
    }

    func testARoutineShowsOnTheDayItWasStampedFor() throws {
        var tree = Tree()
        let thread = tree.add("Routines", todo: false, under: rootID)
        let key = Tree.stampKey("Weekly review", at: date(2026, 11, 16).addingTimeInterval(9 * 3600))
        tree.plant("Weekly review", todo: true, under: thread.id, from: key)
        let entry = try XCTUnwrap(CalendarEntry.all(in: tree, calendar: calendar).first)
        XCTAssertTrue(entry.isRoutine)
        XCTAssertEqual(entry.when, date(2026, 11, 16))
        XCTAssertNil(CalendarEntry.occurrence(of: "mail:M1234"))
    }

    // MARK: The grid

    func testABudWithWhenAndDueIsABarCutAtEachWeeksEnd() throws {
        let tree = Self.world()
        let grid = MonthGrid(month: CalendarMonth(containing: now, now: now, calendar: calendar), entries: CalendarEntry.all(in: tree, calendar: calendar), state: CalendarState())
        let issue = try XCTUnwrap(tree.walk(under: rootID).first { $0.text == "Send the first issue" })
        let pieces = grid.bars.filter { $0.entry == issue.id }
        XCTAssertEqual(pieces.map(\.row), [1, 2, 3, 4], "Friday 6 to Monday 23: four rows")
        XCTAssertEqual(pieces.map { $0.from...$0.to }, [4...6, 0...6, 0...6, 0...0])
        XCTAssertEqual(pieces.map(\.starts), [true, false, false, false], "The arrow on the first piece")
        XCTAssertEqual(pieces.map(\.dueLabel), [nil, nil, nil, "due 23 Nov"], "The flag on the last")
        XCTAssertEqual(pieces.map(\.tone), [.leaf, .leaf, .leaf, .leaf])
        XCTAssertEqual(pieces.map(\.lane), [0, 0, 0, 0], "The longer bar keeps the top lane")
        XCTAssertEqual(pieces.map(\.id), pieces.map { "\(issue.id)-\($0.row)" })
        XCTAssertEqual(pieces[0].columns, 3)
        let onboarding = try XCTUnwrap(tree.walk(under: rootID).first { $0.text == "Review the onboarding flow" })
        let others = grid.bars.filter { $0.entry == onboarding.id }
        XCTAssertEqual(others.map(\.row), [1, 2], "Wednesday 4 to Saturday 14")
        XCTAssertEqual(others.map { $0.from...$0.to }, [2...6, 0...5])
        XCTAssertEqual(others.map(\.lane), [1, 1], "Under the longer bar where they share a row")
        XCTAssertEqual(others.map(\.tone), [.amethyst, .amethyst])
        XCTAssertEqual(grid.lanes, [0, 2, 2, 1, 1, 0])
    }

    func testABudWithOneDateIsAnItemOnItsDay() throws {
        let tree = Self.world()
        let grid = MonthGrid(month: CalendarMonth(containing: now, now: now, calendar: calendar), entries: CalendarEntry.all(in: tree, calendar: calendar), state: CalendarState())
        XCTAssertEqual(grid.items(row: 1, column: 1).map(\.title), ["A walk before the first meeting"], "Scheduled today")
        XCTAssertEqual(grid.items(row: 1, column: 1).map(\.isDue), [false])
        XCTAssertEqual(grid.items(row: 1, column: 1).map(\.tone), [.rose])
        XCTAssertEqual(grid.items(row: 1, column: 3).map(\.title), ["Pick a name"], "Due on Thursday")
        XCTAssertEqual(grid.items(row: 1, column: 3).map(\.isDue), [true])
        XCTAssertEqual(grid.items(row: 1, column: 0).map(\.title), ["Verify the address"], "Overdue since Monday")
        XCTAssertEqual(grid.items.count, 3)
        XCTAssertTrue(grid.items.allSatisfy { !$0.isDone })
        XCTAssertFalse(grid.items.contains { $0.title == "Send the first issue" }, "A bar is not an item too")
    }

    func testADayOutsideTheGridDrawsNothingAndABarIsClippedToIt() throws {
        var tree = Tree()
        let thread = tree.add("Moving", todo: true, under: rootID)
        let far = tree.add("Far away", todo: true, under: thread.id)
        tree.setDue(far.id, date(2027, 3, 1))
        let long = tree.add("Across the turn of the year", todo: true, under: thread.id)
        tree.setWhen(long.id, date(2026, 10, 1))
        tree.setDue(long.id, date(2027, 1, 10))
        let grid = MonthGrid(month: CalendarMonth(containing: now, now: now, calendar: calendar), entries: CalendarEntry.all(in: tree, calendar: calendar), state: CalendarState())
        XCTAssertTrue(grid.items.isEmpty)
        XCTAssertEqual(grid.bars.map(\.row), [0, 1, 2, 3, 4, 5], "Every row, edge to edge")
        XCTAssertTrue(grid.bars.allSatisfy { $0.from == 0 && $0.to == 6 })
        XCTAssertFalse(grid.bars[0].starts, "It started before the grid")
        XCTAssertTrue(grid.bars.allSatisfy { $0.dueLabel == nil }, "And is due after it")
    }

    func testBothDatesOnOneDayMakeAnItemWithTheFlag() throws {
        var tree = Tree()
        let thread = tree.add("Health reset", todo: true, under: rootID)
        let bud = tree.add("Bloodwork", todo: true, under: thread.id)
        tree.setWhen(bud.id, date(2026, 11, 20).addingTimeInterval(8 * 3600))
        tree.setDue(bud.id, date(2026, 11, 20).addingTimeInterval(17 * 3600))
        let month = CalendarMonth(containing: now, now: now, calendar: calendar)
        let entries = CalendarEntry.all(in: tree, calendar: calendar)
        let grid = MonthGrid(month: month, entries: entries, state: CalendarState())
        XCTAssertTrue(grid.bars.isEmpty)
        XCTAssertEqual(grid.items.map(\.isDue), [true])
        XCTAssertEqual(grid.items.map(\.column), [4])
        var state = CalendarState()
        state.toggle(.due)
        XCTAssertEqual(MonthGrid(month: month, entries: entries, state: state).items.map(\.isDue), [false], "Due off: the day is its scheduled one")
    }

    // MARK: The threads and the switches

    func testHidingAThreadTakesItsBudsOutAtOnce() throws {
        let tree = Self.world()
        let month = CalendarMonth(containing: now, now: now, calendar: calendar)
        let entries = CalendarEntry.all(in: tree, calendar: calendar)
        let newsletter = try XCTUnwrap(tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        var state = CalendarState()
        XCTAssertTrue(state.shows(thread: newsletter.id))
        state.toggle(thread: newsletter.id)
        XCTAssertFalse(state.shows(thread: newsletter.id))
        let grid = MonthGrid(month: month, entries: entries, state: state)
        XCTAssertFalse(grid.bars.contains { $0.title == "Send the first issue" })
        XCTAssertFalse(grid.items.contains { $0.title == "Pick a name" })
        XCTAssertTrue(grid.bars.contains { $0.title == "Review the onboarding flow" }, "Another thread's bars stay")
        XCTAssertEqual(grid.lanes[2], 1, "And move up to the top lane")
        XCTAssertTrue(grid.items.contains { $0.title == "A walk before the first meeting" })
        state.toggle(thread: newsletter.id)
        XCTAssertEqual(MonthGrid(month: month, entries: entries, state: state), MonthGrid(month: month, entries: entries, state: CalendarState()), "Back on, as before")
    }

    func testTheWhenAndDueSwitchesHideEachDate() throws {
        let tree = Self.world()
        let month = CalendarMonth(containing: now, now: now, calendar: calendar)
        let entries = CalendarEntry.all(in: tree, calendar: calendar)
        var state = CalendarState()
        state.toggle(.when)
        var grid = MonthGrid(month: month, entries: entries, state: state)
        XCTAssertFalse(grid.items.contains { $0.title == "A walk before the first meeting" }, "Scheduled only: gone")
        XCTAssertTrue(grid.items.contains { $0.title == "Pick a name" }, "Due only: stays")
        XCTAssertTrue(grid.bars.isEmpty, "A bar needs both days")
        XCTAssertEqual(grid.items.filter { $0.title == "Send the first issue" }.map { ($0.row, $0.column, $0.isDue) }.map { "\($0.0),\($0.1),\($0.2)" }, ["4,0,true"], "A bar with When off is an item on its due day")
        state.toggle(.when)
        state.toggle(.due)
        grid = MonthGrid(month: month, entries: entries, state: state)
        XCTAssertTrue(grid.items.contains { $0.title == "A walk before the first meeting" })
        XCTAssertFalse(grid.items.contains { $0.title == "Pick a name" })
        XCTAssertEqual(grid.items.filter { $0.title == "Send the first issue" }.map { "\($0.row),\($0.column),\($0.isDue)" }, ["1,4,false"], "With Due off, on its scheduled day")
        state.toggle(.when)
        XCTAssertTrue(MonthGrid(month: month, entries: entries, state: state).items.isEmpty, "Both off: nothing dated shows")
    }

    func testDoneStartsOffAndRoutinesStartOn() throws {
        var tree = Tree()
        let thread = tree.add("Routines", todo: false, under: rootID)
        let done = tree.add("Done already", todo: true, under: thread.id)
        tree.setWhen(done.id, date(2026, 11, 3))
        tree.toggle(done.id)
        let key = Tree.stampKey("Weekly review", at: date(2026, 11, 16).addingTimeInterval(9 * 3600))
        tree.plant("Weekly review", todo: true, under: thread.id, from: key)
        let month = CalendarMonth(containing: now, now: now, calendar: calendar)
        let entries = CalendarEntry.all(in: tree, calendar: calendar)
        var state = CalendarState()
        XCTAssertFalse(state.shows(.done))
        XCTAssertTrue(state.shows(.routines))
        var grid = MonthGrid(month: month, entries: entries, state: state)
        XCTAssertEqual(grid.items.map(\.title), ["Weekly review"])
        state.toggle(.done)
        grid = MonthGrid(month: month, entries: entries, state: state)
        XCTAssertEqual(grid.items.map(\.title), ["Done already", "Weekly review"])
        XCTAssertEqual(grid.items.map(\.isDone), [true, false])
        state.toggle(.routines)
        grid = MonthGrid(month: month, entries: entries, state: state)
        XCTAssertEqual(grid.items.map(\.title), ["Done already"])
    }

    func testTheStateIsKeptOnThisDeviceAndLoadsWithDefaultsForWhatIsMissing() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "calendar-state-tests"))
        defaults.removePersistentDomain(forName: "calendar-state-tests")
        XCTAssertEqual(CalendarState.load(from: defaults), CalendarState(), "Nothing saved: the defaults")
        var state = CalendarState()
        state.range = .week
        state.layout = .timeline
        state.toggle(.done)
        let thread = UUID()
        state.toggle(thread: thread)
        state.save(to: defaults)
        XCTAssertEqual(CalendarState.load(from: defaults), state)
        XCTAssertEqual(CalendarState.load(from: defaults).hiddenThreads, [thread])
        XCTAssertTrue(CalendarState.load(from: defaults).shows(.done))
        let old = try JSONDecoder().decode(CalendarState.self, from: Data(#"{"range":"Year"}"#.utf8))
        XCTAssertEqual(old.range, .year)
        XCTAssertEqual(old.shown, [.when, .due, .routines], "A field saved before it existed keeps its default")
        defaults.removePersistentDomain(forName: "calendar-state-tests")
    }
}

#if canImport(SwiftUI)
/// The store's side, which exists only where SwiftUI does: a toggle on the store changes what
/// the grid draws in the same turn.
@MainActor
final class CalendarStoreTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_GB")
        c.firstWeekday = 2
        return c
    }

    private func makeStore() -> BudStore {
        let clock: @Sendable () -> Date = { Tree.stillNow }
        let tree = CalendarMonthTests.world()
        let devices = DeviceStore(peers: MemoryPeers.forLaunch(arguments: [], now: clock), now: clock)
        let store = BudStore(vault: MemoryVault(tree: tree), tree: tree, devices: devices)
        XCTAssertEqual(store.now, Tree.stillNow, "The device store's clock is the one clock")
        store.dateCalendar = calendar
        store.calendar = CalendarState()
        return store
    }

    func testTogglingAThreadOrASwitchHidesItsBudsAtOnce() throws {
        let store = makeStore()
        defer { store.calendar = CalendarState() }
        XCTAssertEqual(store.monthGrid.month.title, "November 2026")
        XCTAssertEqual(store.calendarThreads.map(\.title).prefix(2), ["Launch the newsletter", "Q4 roadmap"])
        let newsletter = try XCTUnwrap(store.calendarThreads.first)
        XCTAssertTrue(store.monthGrid.bars.contains { $0.title == "Send the first issue" })
        store.toggleThread(newsletter.id)
        XCTAssertFalse(store.calendar.shows(thread: newsletter.id))
        XCTAssertFalse(store.monthGrid.bars.contains { $0.title == "Send the first issue" })
        XCTAssertFalse(store.monthGrid.items.contains { $0.title == "Pick a name" })
        store.toggleThread(newsletter.id)
        XCTAssertTrue(store.monthGrid.bars.contains { $0.title == "Send the first issue" })
        store.toggle(.when)
        XCTAssertFalse(store.calendar.shows(.when))
        XCTAssertFalse(store.monthGrid.items.contains { $0.title == "A walk before the first meeting" })
        XCTAssertTrue(store.monthGrid.bars.isEmpty)
        store.toggle(.when)
        XCTAssertTrue(store.monthGrid.items.contains { $0.title == "A walk before the first meeting" })
        XCTAssertEqual(CalendarState.load(from: .standard), store.calendar, "The choice is kept on this device")
    }

    func testTheCalendarMovesByMonthsAndComesBackToToday() {
        let store = makeStore()
        XCTAssertNil(store.calendarDate)
        store.shiftCalendar(months: 1)
        XCTAssertEqual(store.monthGrid.month.title, "December 2026")
        store.shiftCalendar(months: 1)
        XCTAssertEqual(store.monthGrid.month.title, "January 2027")
        store.shiftCalendar(months: -3)
        XCTAssertEqual(store.monthGrid.month.title, "October 2026")
        store.calendarToday()
        XCTAssertNil(store.calendarDate)
        XCTAssertEqual(store.monthGrid.month.title, "November 2026")
        XCTAssertTrue(store.monthGrid.month.weeks[1][1].isToday)
    }
}
#endif
