import XCTest
@testable import BudKit

/// The timeline's pure model: the axis and its columns for the month, the quarter and the year,
/// one row per bud under its thread, bars clipped at the edges, points on their day, and the
/// threads folding to their header.
final class TimelineTests: XCTestCase {
    /// A Monday-first calendar in UTC, so every day lands where the board draws it.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_GB")
        c.firstWeekday = 2
        return c
    }

    private var now: Date { Tree.stillNow }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// The month world's timeline for a range, with the defaults or a state of the test's own.
    private func timeline(_ range: CalendarRange, around date: Date? = nil, tree: Tree? = nil, state: CalendarState = CalendarState()) throws -> Timeline {
        let tree = tree ?? CalendarMonthTests.world()
        return try XCTUnwrap(Timeline(
            range: range, containing: date ?? now, now: now,
            entries: CalendarEntry.all(in: tree, calendar: calendar), threads: CalendarThread.list(in: tree),
            state: state, calendar: calendar
        ))
    }

    // MARK: The axis

    func testTheMonthIsAColumnADayWithTheWeekendsShaded() throws {
        let month = try timeline(.month)
        XCTAssertEqual(month.unit, .day)
        XCTAssertEqual(month.start, date(2026, 11, 1))
        XCTAssertEqual(month.end, date(2026, 12, 1))
        XCTAssertEqual(month.days, 30)
        XCTAssertEqual(month.columns.count, 30)
        XCTAssertEqual(month.columns.map(\.label).prefix(3), ["1", "2", "3"])
        XCTAssertEqual(month.columns.last?.label, "30")
        XCTAssertEqual(month.columns.map(\.day), Array(0..<30))
        XCTAssertEqual(month.today, 2, "Tuesday 3 November")
        XCTAssertEqual(month.columns.filter(\.isToday).map(\.label), ["3"])
        XCTAssertEqual(month.shaded, [0...0, 6...7, 13...14, 20...21, 27...28], "Sunday the 1st, then each weekend")
        XCTAssertEqual(month.position(ofDay: 15), 0.5)
    }

    func testTheQuarterIsAColumnAWeekFromItsFirstMonday() throws {
        let quarter = try timeline(.quarter)
        XCTAssertEqual(quarter.unit, .week)
        XCTAssertEqual(quarter.start, date(2026, 10, 1))
        XCTAssertEqual(quarter.end, date(2027, 1, 1))
        XCTAssertEqual(quarter.days, 92)
        XCTAssertEqual(quarter.columns.map(\.label), ["5 Oct", "12 Oct", "19 Oct", "26 Oct", "2 Nov", "9 Nov", "16 Nov", "23 Nov", "30 Nov", "7 Dec", "14 Dec", "21 Dec", "28 Dec"])
        XCTAssertEqual(quarter.columns.first?.day, 4, "October 2026 opens on a Thursday")
        XCTAssertEqual(quarter.today, 33)
        XCTAssertEqual(quarter.columns.filter(\.isToday).map(\.label), ["2 Nov"])
        XCTAssertEqual(quarter.shaded, [0...0, 31...31, 61...61], "Each month's first day")
        XCTAssertEqual(Timeline.subtitle(of: .quarter, containing: now, calendar: calendar), "October – December")
        XCTAssertNil(Timeline.subtitle(of: .month, containing: now, calendar: calendar))
        XCTAssertNil(Timeline.subtitle(of: .year, containing: now, calendar: calendar))
    }

    func testTheYearIsAColumnAMonth() throws {
        let year = try timeline(.year)
        XCTAssertEqual(year.unit, .month)
        XCTAssertEqual(year.start, date(2026, 1, 1))
        XCTAssertEqual(year.end, date(2027, 1, 1))
        XCTAssertEqual(year.days, 365)
        XCTAssertEqual(year.columns.map(\.label), ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"])
        XCTAssertEqual(year.columns.map(\.day), [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334])
        XCTAssertEqual(year.columns.filter(\.isToday).map(\.label), ["Nov"])
        XCTAssertTrue(year.shaded.isEmpty)
        XCTAssertEqual(year.today, 306)
    }

    func testTheRangesWithoutATimelineGiveNone() {
        let tree = CalendarMonthTests.world()
        for range in [CalendarRange.day, .week, .custom] {
            XCTAssertNil(Timeline.Unit(range: range))
            XCTAssertNil(Timeline(range: range, containing: now, now: now, entries: [], threads: CalendarThread.list(in: tree), state: CalendarState(), calendar: calendar))
        }
    }

    func testTodayIsOffTheAxisWhenTheRangeIsElsewhere() throws {
        let next = try timeline(.month, around: date(2026, 12, 15))
        XCTAssertEqual(next.start, date(2026, 12, 1))
        XCTAssertEqual(next.days, 31)
        XCTAssertNil(next.today)
        XCTAssertFalse(next.columns.contains(where: \.isToday))
        let leap = try timeline(.year, around: date(2028, 6, 1))
        XCTAssertEqual(leap.days, 366)
        XCTAssertEqual(leap.columns[2].day, 60)
    }

    // MARK: The rows

    func testOneRowPerBudUnderItsThreadABarForTwoDaysAPointForOne() throws {
        let month = try timeline(.month)
        XCTAssertEqual(month.threads.map(\.title), ["Launch the newsletter", "Q4 roadmap", "Health reset"], "Threads with a bud in the month, in their order")
        XCTAssertEqual(month.threads.map(\.tone), [.leaf, .amethyst, .rose], "Coloured by their place under the centre")
        let newsletter = month.threads[0]
        XCTAssertEqual(newsletter.rows.map(\.title), ["Pick a name", "Verify the address", "Send the first issue"], "In reading order")
        let name = newsletter.rows[0]
        XCTAssertTrue(name.isPoint)
        XCTAssertEqual(name.from, 4, "Due Thursday the 5th")
        XCTAssertEqual(name.to, 4)
        XCTAssertTrue(name.isDue)
        XCTAssertEqual(newsletter.rows[1].from, 1, "Due yesterday, Monday the 2nd")
        let issue = newsletter.rows[2]
        XCTAssertFalse(issue.isPoint)
        XCTAssertEqual(issue.from, 5, "Scheduled Friday the 6th")
        XCTAssertEqual(issue.to, 22, "Due Monday the 23rd")
        XCTAssertEqual(issue.days, 18)
        XCTAssertFalse(issue.startsBefore)
        XCTAssertFalse(issue.endsAfter)
        XCTAssertEqual(newsletter.from, 1)
        XCTAssertEqual(newsletter.to, 22, "The rail spans the thread's rows")
        let roadmap = month.threads[1]
        XCTAssertEqual(roadmap.rows.map(\.title), ["Review the onboarding flow"])
        XCTAssertEqual(roadmap.rows[0].from, 3)
        XCTAssertEqual(roadmap.rows[0].to, 13)
        let health = month.threads[2]
        XCTAssertEqual(health.rows.map(\.title), ["A walk before the first meeting"])
        XCTAssertTrue(health.rows[0].isPoint)
        XCTAssertEqual(health.rows[0].from, 2, "Scheduled today")
        XCTAssertFalse(health.rows[0].isDue)
        XCTAssertEqual(month.rowCount, 8, "Three headers and five rows")
    }

    func testABarPastTheEdgeIsClippedAndDrawsFlatThere() throws {
        var tree = CalendarMonthTests.world()
        let roadmap = try XCTUnwrap(tree.children(of: rootID).first { $0.text == "Q4 roadmap" })
        let long = tree.add("Ship the release", todo: true, under: roadmap.id)
        tree.setWhen(long.id, date(2026, 10, 20))
        tree.setDue(long.id, date(2026, 12, 4))
        let month = try timeline(.month, tree: tree)
        let row = try XCTUnwrap(month.threads[1].rows.first { $0.title == "Ship the release" })
        XCTAssertEqual(row.from, 0)
        XCTAssertEqual(row.to, 29)
        XCTAssertTrue(row.startsBefore)
        XCTAssertTrue(row.endsAfter)
        XCTAssertEqual(month.threads[1].from, 0, "The rail follows the clipped bar")
        XCTAssertEqual(month.threads[1].to, 29)
        let quarter = try timeline(.quarter, tree: tree)
        let whole = try XCTUnwrap(quarter.threads[1].rows.first { $0.title == "Ship the release" })
        XCTAssertEqual(whole.from, 19, "20 October")
        XCTAssertEqual(whole.to, 64, "4 December")
        XCTAssertFalse(whole.startsBefore)
        XCTAssertFalse(whole.endsAfter)
    }

    func testABudOutsideTheRangeHasNoRowAndItsThreadNoneEither() throws {
        let december = try timeline(.month, around: date(2026, 12, 15))
        XCTAssertEqual(december.threads.map(\.title), [], "Nothing in the seed is dated in December")
        let year = try timeline(.year)
        XCTAssertEqual(year.threads.map(\.title), ["Launch the newsletter", "Q4 roadmap", "Health reset"])
        XCTAssertEqual(year.threads[0].rows.map(\.title), ["Pick a name", "Verify the address", "Send the first issue"])
        XCTAssertEqual(year.threads[0].rows[2].from, 309, "6 November")
        XCTAssertEqual(year.threads[0].rows[2].to, 326)
    }

    func testBothDatesOnOneDayMakeAPointWithTheFlag() throws {
        var tree = CalendarMonthTests.world()
        let health = try XCTUnwrap(tree.children(of: rootID).first { $0.text == "Health reset" })
        let both = tree.add("Dentist", todo: true, under: health.id)
        tree.setWhen(both.id, date(2026, 11, 10).addingTimeInterval(9 * 3600))
        tree.setDue(both.id, date(2026, 11, 10).addingTimeInterval(17 * 3600))
        let month = try timeline(.month, tree: tree)
        let row = try XCTUnwrap(month.threads[2].rows.first { $0.title == "Dentist" })
        XCTAssertTrue(row.isPoint)
        XCTAssertEqual(row.from, 9)
        XCTAssertTrue(row.isDue)
    }

    func testTheSwitchesAndHiddenThreadsLeaveRowsOut() throws {
        var state = CalendarState()
        state.toggle(.due)
        let whenOnly = try timeline(.month, state: state)
        let issue = try XCTUnwrap(whenOnly.threads[0].rows.first { $0.title == "Send the first issue" })
        XCTAssertTrue(issue.isPoint, "With Due off, a bar is a point on its scheduled day")
        XCTAssertEqual(issue.from, 5)
        XCTAssertFalse(issue.isDue)
        XCTAssertFalse(whenOnly.threads[0].rows.contains { $0.title == "Pick a name" }, "Due only: gone")
        var hidden = CalendarState()
        let tree = CalendarMonthTests.world()
        let newsletter = try XCTUnwrap(tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        hidden.toggle(thread: newsletter.id)
        let without = try timeline(.month, state: hidden)
        XCTAssertEqual(without.threads.map(\.title), ["Q4 roadmap", "Health reset"], "A hidden thread has no rows at all")
    }

    func testDoneAndRoutinesReadOnTheirRows() throws {
        var tree = Tree()
        let thread = tree.add("Routines", todo: false, under: rootID)
        let done = tree.add("Done already", todo: true, under: thread.id)
        tree.setWhen(done.id, date(2026, 11, 3))
        tree.toggle(done.id)
        let key = Tree.stampKey("Weekly review", at: date(2026, 11, 16).addingTimeInterval(9 * 3600))
        tree.plant("Weekly review", todo: true, under: thread.id, from: key)
        var state = CalendarState()
        state.toggle(.done)
        let month = try timeline(.month, tree: tree, state: state)
        XCTAssertEqual(month.threads.map(\.title), ["Routines"])
        XCTAssertEqual(month.threads[0].rows.map(\.title), ["Done already", "Weekly review"])
        XCTAssertEqual(month.threads[0].rows.map(\.isDone), [true, false])
        XCTAssertEqual(month.threads[0].rows.map(\.isRoutine), [false, true])
        XCTAssertEqual(month.threads[0].rows.map(\.from), [2, 15])
    }

    // MARK: Folding

    func testAThreadFoldsToItsHeaderAndKeepsItsRail() throws {
        let tree = CalendarMonthTests.world()
        let newsletter = try XCTUnwrap(tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        var state = CalendarState()
        XCTAssertFalse(state.isCollapsed(thread: newsletter.id))
        state.toggle(collapsed: newsletter.id)
        XCTAssertTrue(state.isCollapsed(thread: newsletter.id))
        let month = try timeline(.month, tree: tree, state: state)
        let folded = month.threads[0]
        XCTAssertTrue(folded.isCollapsed)
        XCTAssertEqual(folded.rows.count, 3, "The rows are kept")
        XCTAssertTrue(folded.shownRows.isEmpty, "And none is drawn")
        XCTAssertEqual(folded.from, 1)
        XCTAssertEqual(folded.to, 22, "The rail still spans them")
        XCTAssertFalse(month.threads[1].isCollapsed, "The other threads stay open")
        XCTAssertEqual(month.rowCount, 5)
        state.toggle(collapsed: newsletter.id)
        XCTAssertEqual(try timeline(.month, tree: tree, state: state), try timeline(.month, tree: tree), "Open again, as before")
    }

    func testTheFoldedThreadsAreKeptOnThisDevice() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "timeline-state-tests"))
        defaults.removePersistentDomain(forName: "timeline-state-tests")
        var state = CalendarState()
        let thread = UUID()
        state.toggle(collapsed: thread)
        state.save(to: defaults)
        XCTAssertEqual(CalendarState.load(from: defaults).collapsedThreads, [thread])
        let old = try JSONDecoder().decode(CalendarState.self, from: Data(#"{"range":"Quarter","hiddenThreads":[]}"#.utf8))
        XCTAssertTrue(old.collapsedThreads.isEmpty, "A state saved before folding existed opens every thread")
        defaults.removePersistentDomain(forName: "timeline-state-tests")
    }
}

#if canImport(SwiftUI)
/// The store's side, which exists only where SwiftUI does: folding a thread from its header
/// changes what the timeline draws in the same turn, and the fold is kept on this device.
@MainActor
final class TimelineStoreTests: XCTestCase {
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
        let devices = DeviceStore(peers: MemoryPeers.forLaunch(arguments: [], now: clock), now: clock, calendar: calendar)
        let store = BudStore(vault: MemoryVault(tree: tree), tree: tree, devices: devices)
        store.calendarState = CalendarState(range: .month, layout: .timeline)
        return store
    }

    func testFoldingAThreadFromItsHeaderHidesItsRowsAtOnce() throws {
        let store = makeStore()
        defer { store.calendarState = CalendarState() }
        let timeline = try XCTUnwrap(store.timeline)
        XCTAssertEqual(timeline.unit, .day)
        XCTAssertEqual(timeline.threads.map(\.title), ["Launch the newsletter", "Q4 roadmap", "Health reset"])
        let newsletter = try XCTUnwrap(timeline.threads.first)
        XCTAssertEqual(newsletter.shownRows.map(\.title), ["Pick a name", "Verify the address", "Send the first issue"])
        store.toggleCollapsed(newsletter.id)
        XCTAssertTrue(store.calendarState.isCollapsed(thread: newsletter.id))
        let folded = try XCTUnwrap(store.timeline?.threads.first)
        XCTAssertTrue(folded.isCollapsed)
        XCTAssertTrue(folded.shownRows.isEmpty)
        XCTAssertEqual(folded.to, 22, "The rail stays")
        XCTAssertEqual(CalendarState.load(from: .standard).collapsedThreads, [newsletter.id], "The fold is kept on this device")
        store.toggleCollapsed(newsletter.id)
        XCTAssertEqual(store.timeline?.threads.first?.shownRows.count, 3)
        XCTAssertTrue(store.calendarState.collapsedThreads.isEmpty)
    }

    func testTheTimelineFollowsTheRangeAndTheFocus() throws {
        let store = makeStore()
        defer { store.calendarState = CalendarState() }
        store.calendarState.range = .quarter
        XCTAssertEqual(store.timeline?.unit, .week)
        XCTAssertEqual(store.timeline?.columns.first?.label, "5 Oct")
        XCTAssertEqual(store.calendarSubtitle, "October – December")
        store.calendarState.range = .year
        XCTAssertEqual(store.timeline?.unit, .month)
        XCTAssertEqual(store.timeline?.columns.count, 12)
        XCTAssertNil(store.calendarSubtitle)
        store.shiftCalendar(by: 1)
        XCTAssertNil(store.timeline?.today, "Next year: today is off the axis")
        store.calendarState.range = .week
        XCTAssertNil(store.timeline, "The week has no timeline yet")
    }
}
#endif
