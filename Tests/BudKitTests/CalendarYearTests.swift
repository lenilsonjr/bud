import XCTest
@testable import BudKit

/// The year's small months and the custom range: the months and their shading and dots, the
/// range's title and step, the picker's presets and taps, and what the state keeps.
final class CalendarYearTests: XCTestCase {
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

    private func ym(_ year: Int, _ month: Int) -> YearMonth { YearMonth(year: year, month: month) }

    /// The seed world with its two long buds, as the month tests build it.
    private func yearGrid(state: CalendarState = CalendarState()) -> YearGrid {
        YearGrid(year: 2026, entries: CalendarEntry.all(in: CalendarMonthTests.world(), calendar: calendar), state: state, now: now, calendar: calendar)
    }

    // MARK: Months

    func testAMonthRollsIntoTheNextOrPreviousYear() {
        XCTAssertEqual(ym(2026, 13), ym(2027, 1))
        XCTAssertEqual(ym(2026, 0), ym(2025, 12))
        XCTAssertEqual(ym(2026, 11).adding(3), ym(2027, 2))
        XCTAssertEqual(ym(2026, 11).adding(-11), ym(2025, 12))
        XCTAssertEqual(ym(2027, 2).months(since: ym(2026, 11)), 3)
        XCTAssertLessThan(ym(2026, 12), ym(2027, 1))
        XCTAssertEqual(YearMonth(containing: now, calendar: calendar), ym(2026, 11))
        XCTAssertEqual(ym(2026, 11).start(calendar: calendar), date(2026, 11, 1))
        XCTAssertEqual(ym(2026, 11).text("MMM yyyy", calendar: calendar), "Nov 2026")
    }

    func testARangeRunsFromItsFirstMonthToItsLastInEitherOrder() {
        let range = CustomRange(first: ym(2027, 2), last: ym(2026, 11))
        XCTAssertEqual(range.first, ym(2026, 11))
        XCTAssertEqual(range.last, ym(2027, 2))
        XCTAssertEqual(range.months, 4)
        XCTAssertEqual(range.all, [ym(2026, 11), ym(2026, 12), ym(2027, 1), ym(2027, 2)])
        XCTAssertTrue(range.contains(ym(2027, 1)))
        XCTAssertFalse(range.contains(ym(2027, 3)))
        XCTAssertEqual(range.start(calendar: calendar), date(2026, 11, 1))
        XCTAssertEqual(range.end(calendar: calendar), date(2027, 3, 1), "The day after the last month")
        XCTAssertEqual(CustomRange(from: ym(2026, 11), months: 3).last, ym(2027, 1))
        XCTAssertEqual(CustomRange(from: ym(2026, 11), months: 0).months, 1, "At least one month")
    }

    func testARangeIsTitledAsTheBoardWritesItAndStepsByItsOwnLength() {
        let range = CustomRange(first: ym(2026, 11), last: ym(2027, 2))
        XCTAssertEqual(range.title(calendar: calendar), "Nov 2026 – Feb 2027")
        XCTAssertEqual(range.lengthLine, "4 months")
        XCTAssertEqual(CustomRange(first: ym(2026, 11), last: ym(2026, 12)).title(calendar: calendar), "Nov – Dec 2026", "One year, written once")
        XCTAssertEqual(CustomRange(first: ym(2026, 11), last: ym(2026, 11)).title(calendar: calendar), "November 2026")
        XCTAssertEqual(CustomRange(first: ym(2026, 11), last: ym(2026, 11)).lengthLine, "1 month")
        XCTAssertEqual(range.shifted(by: 1), CustomRange(first: ym(2027, 3), last: ym(2027, 6)))
        XCTAssertEqual(range.shifted(by: -1), CustomRange(first: ym(2026, 7), last: ym(2026, 10)))
        XCTAssertEqual(CalendarRange.custom.title(for: now, custom: range, calendar: calendar), "Nov 2026 – Feb 2027")
        XCTAssertEqual(CalendarRange.custom.title(for: now, custom: nil, calendar: calendar), "November 2026", "Until a range is picked, the month")
        XCTAssertEqual(CalendarRange.month.title(for: now, custom: range, calendar: calendar), "November 2026", "Only Custom reads the range")
        XCTAssertEqual(CalendarRange.custom.shift(now, by: 1, custom: range, calendar: calendar), date(2027, 3, 3).addingTimeInterval(10 * 3600), "Four months on")
        XCTAssertEqual(CalendarRange.custom.shift(now, by: -1, custom: nil, calendar: calendar), CalendarRange.month.shift(now, by: -1, calendar: calendar))
        XCTAssertEqual(CalendarRange.year.shift(now, by: 1, custom: range, calendar: calendar), CalendarRange.year.shift(now, by: 1, calendar: calendar))
    }

    // MARK: Presets

    func testThePresetsCountFromThisMonth() {
        XCTAssertEqual(CustomRange.nextThreeMonths(from: now, calendar: calendar), CustomRange(first: ym(2026, 11), last: ym(2027, 1)))
        XCTAssertEqual(CustomRange.thisHalf(from: now, calendar: calendar), CustomRange(first: ym(2026, 7), last: ym(2026, 12)))
        XCTAssertEqual(CustomRange.thisHalf(from: date(2027, 3, 15), calendar: calendar), CustomRange(first: ym(2027, 1), last: ym(2027, 6)))
        XCTAssertEqual(CustomRange.until(date(2027, 2, 10), from: now, calendar: calendar), CustomRange(first: ym(2026, 11), last: ym(2027, 2)))
        XCTAssertEqual(CustomRange.until(date(2026, 10, 1), from: now, calendar: calendar), CustomRange(first: ym(2026, 11), last: ym(2026, 11)), "A due day gone by: this month alone")
    }

    func testThePickerListsTheTwoFixedPresetsThenOnePerThreadDueAhead() {
        let threads: [(title: String, due: Date?)] = [
            ("Moving to Lisbon", date(2027, 2, 10)),
            ("Q4 roadmap", nil),
            ("Last year's push", date(2026, 10, 1)),
            ("Health reset", date(2026, 12, 1)),
        ]
        let presets = RangePreset.all(now: now, threads: threads, calendar: calendar)
        XCTAssertEqual(presets.map(\.title), ["Next 3 months", "This half", "Until Health reset is due", "Until Moving to Lisbon is due"], "Nearest due first; a due day gone by is not a preset")
        XCTAssertEqual(presets.map(\.symbol), ["calendar", "calendar", "flag", "flag"])
        XCTAssertEqual(presets[3].range, CustomRange(first: ym(2026, 11), last: ym(2027, 2)))
        XCTAssertEqual(presets[2].range.months, 2)
        XCTAssertEqual(RangePreset.all(now: now, threads: [], calendar: calendar).count, 2)
    }

    func testTappingPicksAFirstMonthThenALastThenStartsOver() {
        var pick = RangePick()
        XCTAssertNil(pick.range)
        XCTAssertEqual(pick.showLine, "Show")
        pick.tap(ym(2027, 2))
        XCTAssertEqual(pick.first, ym(2027, 2))
        XCTAssertNil(pick.range, "One month is not a range yet")
        XCTAssertTrue(pick.isEnd(ym(2027, 2)))
        pick.tap(ym(2026, 11))
        XCTAssertEqual(pick.range, CustomRange(first: ym(2026, 11), last: ym(2027, 2)), "The earlier tap becomes the first")
        XCTAssertEqual(pick.showLine, "Show 4 months")
        XCTAssertTrue(pick.isBetween(ym(2026, 12)))
        XCTAssertFalse(pick.isBetween(ym(2026, 11)))
        XCTAssertTrue(pick.isEnd(ym(2026, 11)))
        pick.tap(ym(2026, 5))
        XCTAssertEqual(pick.first, ym(2026, 5))
        XCTAssertNil(pick.last, "A third tap starts a new range")
        pick.tap(ym(2026, 5))
        XCTAssertEqual(pick.range, CustomRange(first: ym(2026, 5), last: ym(2026, 5)), "The same month twice is one month")
        let open = RangePick(CustomRange(first: ym(2026, 11), last: ym(2027, 2)))
        XCTAssertEqual(open.range?.months, 4, "The picker opens on the range on show")
    }

    func testThePickerLaysOutThisYearAndTheNextStretchedToHoldTheRange() {
        XCTAssertEqual(RangePick.years(now: now, holding: nil, calendar: calendar), [2026, 2027])
        XCTAssertEqual(RangePick.years(now: now, holding: CustomRange(first: ym(2026, 11), last: ym(2027, 2)), calendar: calendar), [2026, 2027])
        XCTAssertEqual(RangePick.years(now: now, holding: CustomRange(first: ym(2025, 6), last: ym(2028, 1)), calendar: calendar), [2025, 2026, 2027, 2028])
    }

    // MARK: The year

    func testTheYearIsTwelveSmallMonthsInRowsOfFour() {
        let grid = yearGrid()
        XCTAssertEqual(grid.months.map(\.title), ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"])
        XCTAssertEqual(grid.rows.map(\.count), [4, 4, 4])
        XCTAssertEqual(grid.weekdays, ["M", "T", "W", "T", "F", "S", "S"])
        let january = grid.months[0]
        XCTAssertEqual(january.weeks.count, 6)
        XCTAssertEqual(january.weeks[0].map { $0?.number }, [nil, nil, nil, 1, 2, 3, 4], "January 2026 starts on a Thursday")
        XCTAssertEqual(january.weeks[4].map { $0?.number }, [26, 27, 28, 29, 30, 31, nil])
        XCTAssertEqual(january.weeks[5].map { $0?.number }, Array(repeating: nil, count: 7), "Six rows, so every month is the same height")
        XCTAssertEqual(january.days.count, 31)
        XCTAssertEqual(grid.months[1].days.count, 28)
        XCTAssertEqual(grid.months[1].weeks[0].map { $0?.number }, [nil, nil, nil, nil, nil, nil, 1], "February 2026 starts on a Sunday")
        XCTAssertTrue(january.isPast)
        XCTAssertFalse(january.isCurrent)
        XCTAssertTrue(grid.months[10].isCurrent, "November")
        XCTAssertFalse(grid.months[10].isPast)
        XCTAssertFalse(grid.months[11].isPast, "December is ahead")
        XCTAssertEqual(grid.month(ym(2026, 11))?.title, "November")
        XCTAssertNil(grid.month(ym(2027, 1)))
    }

    func testTodayIsMarkedAndTheDaysBeforeItAreDim() throws {
        let november = try XCTUnwrap(yearGrid().month(ym(2026, 11)))
        XCTAssertTrue(try XCTUnwrap(november.day(3)).isToday)
        XCTAssertFalse(try XCTUnwrap(november.day(3)).isPast)
        XCTAssertTrue(try XCTUnwrap(november.day(2)).isPast)
        XCTAssertFalse(try XCTUnwrap(november.day(4)).isPast)
        XCTAssertEqual(november.days.filter(\.isToday).count, 1)
        XCTAssertTrue(try XCTUnwrap(yearGrid().month(ym(2026, 10))?.day(31)).isPast)
        XCTAssertEqual(try XCTUnwrap(november.day(1)).date, date(2026, 11, 1))
    }

    func testALongBudShadesItsDaysAndTheShorterOneShowsWhereTheyCross() throws {
        let november = try XCTUnwrap(yearGrid().month(ym(2026, 11)))
        XCTAssertNil(november.day(3)?.shade)
        XCTAssertEqual(november.day(4)?.shade, .amethyst, "The onboarding review from Wednesday 4")
        XCTAssertEqual(november.day(6)?.shade, .amethyst, "The shorter bud shows where both cross")
        XCTAssertEqual(november.day(14)?.shade, .amethyst)
        XCTAssertEqual(november.day(15)?.shade, .leaf, "The first issue alone from Sunday 15")
        XCTAssertEqual(november.day(23)?.shade, .leaf)
        XCTAssertNil(november.day(24)?.shade)
        XCTAssertEqual(november.days.filter { $0.shade != nil }.count, 20)
    }

    func testADayWithABudGetsADotInItsThreadsColour() throws {
        let november = try XCTUnwrap(yearGrid().month(ym(2026, 11)))
        XCTAssertEqual(november.day(3)?.dot, .rose, "A walk before the first meeting, today")
        XCTAssertEqual(november.day(5)?.dot, .leaf, "Pick a name, due Thursday")
        XCTAssertNotNil(november.day(2)?.dot, "Verify the address, overdue")
        XCTAssertEqual(november.day(14)?.dot, .amethyst, "The day the onboarding review is due")
        XCTAssertEqual(november.day(23)?.dot, .leaf, "The day the first issue is due")
        XCTAssertNil(november.day(6)?.dot, "No dot where a long bud starts")
        XCTAssertNil(november.day(10)?.dot)
    }

    func testAHiddenThreadLeavesNoShadeOrDot() throws {
        let tree = CalendarMonthTests.world()
        let newsletter = try XCTUnwrap(tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        var state = CalendarState()
        state.toggle(thread: newsletter.id)
        let november = try XCTUnwrap(yearGrid(state: state).month(ym(2026, 11)))
        XCTAssertNil(november.day(15)?.shade)
        XCTAssertNil(november.day(23)?.dot)
        XCTAssertNil(november.day(5)?.dot)
        XCTAssertEqual(november.day(6)?.shade, .amethyst, "The roadmap's bud still shows")
        var due = CalendarState()
        due.toggle(.due)
        let whenOnly = try XCTUnwrap(yearGrid(state: due).month(ym(2026, 11)))
        XCTAssertNil(whenOnly.day(6)?.shade, "Without Due, a long bud is one day")
        XCTAssertEqual(whenOnly.day(6)?.dot, .leaf, "Its scheduled day")
        XCTAssertNil(whenOnly.day(23)?.dot)
    }

    func testTheCustomRangeIsItsMonthsAlone() {
        let range = CustomRange(first: ym(2026, 11), last: ym(2027, 2))
        let grid = YearGrid(range: range, entries: CalendarEntry.all(in: CalendarMonthTests.world(), calendar: calendar), state: CalendarState(), now: now, calendar: calendar)
        XCTAssertEqual(grid.months.map(\.title), ["November", "December", "January", "February"])
        XCTAssertEqual(grid.months.map(\.month), range.all)
        XCTAssertEqual(grid.rows.map(\.count), [4])
        XCTAssertEqual(grid.month(ym(2026, 11))?.day(15)?.shade, .leaf)
        XCTAssertEqual(grid.months[2].weeks[0].map { $0?.number }, [nil, nil, nil, nil, 1, 2, 3], "January 2027 starts on a Friday")
        XCTAssertEqual(YearGrid(range: CustomRange(from: ym(2026, 1), months: 5), entries: [], state: CalendarState(), now: now, calendar: calendar).rows.map(\.count), [4, 1])
    }

    // MARK: Kept

    func testTheStateKeepsTheCustomRangeAndLoadsWithoutOne() throws {
        let range = CustomRange(first: ym(2026, 11), last: ym(2027, 2))
        let state = CalendarState(range: .custom, custom: range)
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(CalendarState.self, from: data), state)
        let old = try JSONDecoder().decode(CalendarState.self, from: Data(#"{"range":"Custom"}"#.utf8))
        XCTAssertEqual(old.range, .custom)
        XCTAssertNil(old.custom, "A state saved before the picker has no range")
        XCTAssertNil(CalendarState().custom)
    }
}
