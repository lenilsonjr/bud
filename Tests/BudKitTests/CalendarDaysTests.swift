import XCTest
@testable import BudKit

/// The Day and Week views' pure model: the days and their hours, the all-day row of spans and
/// dateless-hour buds, the blocks placed by the hour, and the now line.
final class CalendarDaysTests: XCTestCase {
    /// A Monday-first calendar in UTC, so every day lands where the board draws it.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_GB")
        c.firstWeekday = 2
        return c
    }

    /// Tuesday 3 November 2026, 10:00.
    private var now: Date { Tree.stillNow }

    private func at(_ y: Int, _ m: Int, _ d: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute))!
    }

    /// The seed world with the days the views draw: the onboarding review spanning Monday 2 to
    /// Monday 23 November, the first issue scheduled Tuesday 3 and due Friday 6, the name picked
    /// Tuesday 3 at 14:00 and due by 14:30, the sender address due Tuesday 3 with no time, and the
    /// seed's walk at 10:00 that morning.
    private func world() -> Tree {
        var tree = Tree.seed(now: now)
        let onboarding = tree.walk(under: rootID).first { $0.text == "Review the onboarding flow" }!
        tree.setWhen(onboarding.id, at(2026, 11, 2))
        tree.setDue(onboarding.id, at(2026, 11, 23))
        let newsletter = tree.children(of: rootID).first { $0.text == "Launch the newsletter" }!
        let issue = tree.add("Send the first issue", todo: true, under: newsletter.id)
        tree.setWhen(issue.id, at(2026, 11, 3))
        tree.setDue(issue.id, at(2026, 11, 6))
        let name = tree.walk(under: rootID).first { $0.text == "Pick a name" }!
        tree.setWhen(name.id, at(2026, 11, 3, 14, 0))
        tree.setDue(name.id, at(2026, 11, 3, 14, 30))
        let verify = tree.walk(under: rootID).first { $0.text == "Verify the address" }!
        tree.setDue(verify.id, at(2026, 11, 3))
        return tree
    }

    private func entries(_ tree: Tree) -> [CalendarEntry] { CalendarEntry.all(in: tree, calendar: calendar) }

    private func day(_ tree: Tree, on date: Date? = nil, state: CalendarState = CalendarState(), now: Date? = nil) -> CalendarDays {
        CalendarDays.day(containing: date ?? self.now, now: now ?? self.now, entries: entries(tree), state: state, calendar: calendar)
    }

    private func week(_ tree: Tree, on date: Date? = nil, state: CalendarState = CalendarState(), now: Date? = nil) -> CalendarDays {
        CalendarDays.week(containing: date ?? self.now, now: now ?? self.now, entries: entries(tree), state: state, calendar: calendar)
    }

    // MARK: The days and hours

    func testTheDayIsOneDayWithItsHoursFromSeven() {
        let plan = day(world())
        XCTAssertEqual(plan.days.count, 1)
        XCTAssertEqual(plan.days[0].date, at(2026, 11, 3))
        XCTAssertEqual(plan.days[0].number, 3)
        XCTAssertEqual(plan.days[0].weekday, "TUE")
        XCTAssertTrue(plan.days[0].isToday)
        XCTAssertFalse(plan.days[0].isWeekend)
        XCTAssertEqual(plan.firstHour, 7)
        XCTAssertEqual(plan.lastHour, 21)
        XCTAssertEqual(plan.hourCount, 14)
        XCTAssertEqual(plan.hours.first, "07:00")
        XCTAssertEqual(plan.hours.last, "20:00")
        XCTAssertEqual(plan.hours.count, 14, "The last line has no label: nothing sits under it")
        XCTAssertEqual(plan.position(ofMinutes: 7 * 60), 0)
        XCTAssertEqual(plan.position(ofMinutes: 21 * 60), 1)
        XCTAssertEqual(plan.position(ofMinutes: 14 * 60), 0.5)
    }

    func testTheWeekRunsFromMondayToSunday() {
        let plan = week(world())
        XCTAssertEqual(plan.days.count, 7)
        XCTAssertEqual(plan.days.map(\.number), [2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(plan.days.map(\.weekday), ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"])
        XCTAssertEqual(plan.days.map(\.isToday), [false, true, false, false, false, false, false])
        XCTAssertEqual(plan.days.map(\.isWeekend), [false, false, false, false, false, true, true])
        XCTAssertEqual(week(world(), on: at(2026, 11, 8)).days[0].date, at(2026, 11, 2), "A Sunday belongs to the week that began on Monday")
    }

    func testAMidnightMomentIsAllDayAndOneWithAnHourIsTimed() {
        XCTAssertFalse(CalendarDays.isTimed(at(2026, 11, 3), calendar: calendar))
        XCTAssertTrue(CalendarDays.isTimed(at(2026, 11, 3, 0, 1), calendar: calendar))
        XCTAssertTrue(CalendarDays.isTimed(now, calendar: calendar), "The still clock is ten in the morning")
        XCTAssertEqual(CalendarDays.minutes(of: at(2026, 11, 3, 14, 30), calendar: calendar), 870)
        XCTAssertEqual(CalendarDays.time(870), "14:30")
        XCTAssertEqual(CalendarDays.time(7 * 60), "07:00")
    }

    // MARK: The all-day row

    func testTheDaysAllDayRowCountsTheSpansDaysAndNamesItsDue() throws {
        let plan = day(world())
        XCTAssertEqual(plan.bars.map(\.label), ["Review the onboarding flow · day 2 of 22, due 23 Nov", "Send the first issue · day 1 of 4, due 6 Nov", "Verify the address"], "Spans first, longest first, then the one-day buds")
        XCTAssertEqual(plan.bars.map(\.lane), [0, 1, 2], "Each covers the day, so each takes its own lane")
        XCTAssertEqual(plan.lanes, 3)
        let onboarding = try XCTUnwrap(plan.bars.first)
        XCTAssertEqual(onboarding.from, 0)
        XCTAssertEqual(onboarding.to, 0)
        XCTAssertFalse(onboarding.starts, "It started yesterday")
        XCTAssertFalse(onboarding.ends)
        let issue = plan.bars[1]
        XCTAssertTrue(issue.starts)
        XCTAssertFalse(issue.ends)
        XCTAssertEqual(issue.tone, .leaf)
        let verify = plan.bars[2]
        XCTAssertFalse(verify.starts)
        XCTAssertTrue(verify.ends, "Due today, with no time: in the all-day row with its flag")
    }

    func testTheWeeksBarsRunAcrossTheirColumnsAndPointPastTheWeek() throws {
        let plan = week(world())
        let onboarding = try XCTUnwrap(plan.bars.first { $0.title == "Review the onboarding flow" })
        XCTAssertEqual(onboarding.label, "Review the onboarding flow → 23 Nov", "Due after the week: an arrow to the day")
        XCTAssertEqual(onboarding.from, 0)
        XCTAssertEqual(onboarding.to, 6)
        XCTAssertEqual(onboarding.lane, 0)
        XCTAssertTrue(onboarding.starts)
        XCTAssertFalse(onboarding.ends)
        let issue = try XCTUnwrap(plan.bars.first { $0.title == "Send the first issue" })
        XCTAssertEqual(issue.label, "Send the first issue · due 6 Nov", "Due in the week: the flag and its day")
        XCTAssertEqual(issue.from, 1)
        XCTAssertEqual(issue.to, 4)
        XCTAssertEqual(issue.lane, 1)
        XCTAssertTrue(issue.starts)
        XCTAssertTrue(issue.ends)
        let verify = try XCTUnwrap(plan.bars.first { $0.title == "Verify the address" })
        XCTAssertEqual(verify.label, "Verify the address")
        XCTAssertEqual(verify.from, 1)
        XCTAssertEqual(verify.to, 1)
        XCTAssertEqual(verify.lane, 2, "Under the issue's bar, which crosses its column")
        XCTAssertEqual(plan.lanes, 3)
    }

    func testOneDayBudsShareALaneWhenTheirColumnsDiffer() throws {
        var tree = world()
        let roadmap = tree.children(of: rootID).first { $0.text == "Q4 roadmap" }!
        let notes = tree.add("Launch notes draft", todo: true, under: roadmap.id)
        tree.setWhen(notes.id, at(2026, 11, 5))
        let plan = week(tree)
        let verify = try XCTUnwrap(plan.bars.first { $0.title == "Verify the address" })
        let draft = try XCTUnwrap(plan.bars.first { $0.title == "Launch notes draft" })
        XCTAssertEqual(draft.from, 3)
        XCTAssertEqual(draft.lane, verify.lane, "Thursday is free in the address's lane")
        XCTAssertTrue(draft.starts)
        XCTAssertFalse(draft.ends)
    }

    func testASpanOutsideTheDaysIsLeftOut() {
        let plan = day(world(), on: at(2026, 12, 1))
        XCTAssertTrue(plan.bars.isEmpty)
        XCTAssertTrue(plan.blocks.isEmpty)
        XCTAssertEqual(plan.lanes, 0)
        XCTAssertNil(plan.now)
    }

    // MARK: The hours

    func testATimedBudIsABlockAtItsHour() throws {
        let plan = day(world())
        XCTAssertEqual(plan.blocks.map(\.title), ["A walk before the first meeting", "Pick a name"], "By their start")
        let walk = plan.blocks[0]
        XCTAssertEqual(walk.column, 0)
        XCTAssertEqual(walk.start, 10 * 60)
        XCTAssertEqual(walk.end, 10 * 60 + 30, "No end: half an hour")
        XCTAssertEqual(walk.time, "10:00")
        XCTAssertFalse(walk.isDue)
        XCTAssertEqual(walk.tone, .rose)
        let name = plan.blocks[1]
        XCTAssertEqual(name.start, 14 * 60)
        XCTAssertEqual(name.end, 14 * 60 + 30)
        XCTAssertEqual(name.time, "14:00–14:30", "Scheduled and due on the day: from the one to the other")
        XCTAssertFalse(name.isDue)
        XCTAssertEqual(plan.blocks.map(\.lanes), [1, 1], "Nothing overlaps")
        XCTAssertEqual(plan.blocks(in: 0).count, 2)
    }

    func testTheWeekPlacesBlocksInTheirColumns() throws {
        var tree = world()
        let health = tree.children(of: rootID).first { $0.text == "Health reset" }!
        let run = tree.add("Run", todo: true, under: health.id)
        tree.setWhen(run.id, at(2026, 11, 5, 7, 0))
        tree.setDue(run.id, at(2026, 11, 5, 7, 45))
        let plan = week(tree)
        let block = try XCTUnwrap(plan.blocks.first { $0.title == "Run" })
        XCTAssertEqual(block.column, 3)
        XCTAssertEqual(block.time, "07:00–07:45")
        XCTAssertEqual(plan.blocks(in: 1).map(\.title), ["A walk before the first meeting", "Pick a name"])
        XCTAssertTrue(plan.blocks(in: 0).isEmpty)
    }

    func testADueMomentWithATimeIsABlockOnItsDay() throws {
        var tree = world()
        let name = tree.walk(under: rootID).first { $0.text == "Pick a name" }!
        tree.setWhen(name.id, nil)
        let plan = day(tree)
        let block = try XCTUnwrap(plan.blocks.first { $0.title == "Pick a name" })
        XCTAssertEqual(block.start, 14 * 60 + 30)
        XCTAssertEqual(block.time, "14:30")
        XCTAssertTrue(block.isDue)
        XCTAssertEqual(block.id, "\(name.id)-due")
    }

    func testOverlappingBlocksShareTheirColumn() throws {
        var tree = world()
        let roadmap = tree.children(of: rootID).first { $0.text == "Q4 roadmap" }!
        let sync = tree.add("Roadmap sync", todo: true, under: roadmap.id)
        tree.setWhen(sync.id, at(2026, 11, 3, 10, 15))
        tree.setDue(sync.id, at(2026, 11, 3, 11, 0))
        let notes = tree.add("Release notes", todo: true, under: roadmap.id)
        tree.setWhen(notes.id, at(2026, 11, 3, 10, 30))
        let plan = day(tree)
        let walk = try XCTUnwrap(plan.blocks.first { $0.title == "A walk before the first meeting" })
        let syncBlock = try XCTUnwrap(plan.blocks.first { $0.title == "Roadmap sync" })
        let notesBlock = try XCTUnwrap(plan.blocks.first { $0.title == "Release notes" })
        XCTAssertEqual(walk.lane, 0)
        XCTAssertEqual(syncBlock.lane, 1, "Overlaps the walk")
        XCTAssertEqual(notesBlock.lane, 0, "The walk has ended by half past")
        XCTAssertEqual([walk.lanes, syncBlock.lanes, notesBlock.lanes], [2, 2, 2], "One cluster of three, two wide")
        let name = try XCTUnwrap(plan.blocks.first { $0.title == "Pick a name" })
        XCTAssertEqual(name.lane, 0)
        XCTAssertEqual(name.lanes, 1, "Alone in the afternoon")
    }

    func testTheHoursStretchToHoldAnEarlyOrLateBlock() {
        var tree = world()
        let health = tree.children(of: rootID).first { $0.text == "Health reset" }!
        let early = tree.add("Stretch", todo: true, under: health.id)
        tree.setWhen(early.id, at(2026, 11, 3, 6, 15))
        let late = tree.add("Read", todo: true, under: health.id)
        tree.setWhen(late.id, at(2026, 11, 3, 22, 0))
        tree.setDue(late.id, at(2026, 11, 3, 22, 40))
        let plan = day(tree)
        XCTAssertEqual(plan.firstHour, 6)
        XCTAssertEqual(plan.lastHour, 23)
        XCTAssertEqual(plan.hours.first, "06:00")
        XCTAssertEqual(plan.hours.last, "22:00")
        XCTAssertEqual(plan.position(ofMinutes: 6 * 60), 0)
    }

    // MARK: The now line

    func testTheNowLineSitsOnTodayAtItsMinute() {
        XCTAssertEqual(day(world()).now, CalendarDays.NowMark(column: 0, minutes: 10 * 60))
        XCTAssertEqual(week(world()).now, CalendarDays.NowMark(column: 1, minutes: 10 * 60))
        XCTAssertEqual(week(world()).position(ofMinutes: 10 * 60), 3.0 / 14.0, accuracy: 0.0001)
        XCTAssertNil(day(world(), on: at(2026, 11, 4)).now, "Tomorrow has no now")
        XCTAssertNil(week(world(), on: at(2026, 11, 10)).now)
        XCTAssertNil(day(world(), now: at(2026, 11, 3, 23, 30)).now, "Past the hours drawn")
        XCTAssertEqual(day(world(), now: at(2026, 11, 3, 7, 0)).now?.minutes, 7 * 60, "On the first line")
    }

    // MARK: The switches

    func testTheSwitchesMoveABudBetweenTheRowAndTheHours() throws {
        let tree = world()
        var state = CalendarState()
        state.toggle(.due)
        let noDue = day(tree, state: state)
        XCTAssertEqual(noDue.bars.map(\.label), ["Send the first issue"], "Without Due, a span is its scheduled day alone, and the review's was yesterday")
        let name = try XCTUnwrap(noDue.blocks.first { $0.title == "Pick a name" })
        XCTAssertEqual(name.time, "14:00", "Without Due, no end")
        XCTAssertNil(noDue.blocks.first { $0.title == "Verify the address" })
        state = CalendarState()
        state.toggle(.when)
        let noWhen = day(tree, state: state)
        XCTAssertEqual(noWhen.bars.map(\.label), ["Verify the address"], "The spans' due days are later")
        let due = try XCTUnwrap(noWhen.blocks.first { $0.title == "Pick a name" })
        XCTAssertEqual(due.time, "14:30")
        XCTAssertTrue(due.isDue)
        XCTAssertNil(noWhen.blocks.first { $0.title == "A walk before the first meeting" })
    }

    func testADoneBudShowsOnlyWithDoneOn() throws {
        var tree = world()
        let name = tree.walk(under: rootID).first { $0.text == "Pick a name" }!
        tree.toggle(name.id)
        XCTAssertNil(day(tree).blocks.first { $0.title == "Pick a name" })
        var state = CalendarState()
        state.toggle(.done)
        let block = try XCTUnwrap(day(tree, state: state).blocks.first { $0.title == "Pick a name" })
        XCTAssertTrue(block.isDone)
    }

    func testAHiddenThreadTakesItsBudsOut() {
        let tree = world()
        let newsletter = tree.children(of: rootID).first { $0.text == "Launch the newsletter" }!
        var state = CalendarState()
        state.toggle(thread: newsletter.id)
        let plan = week(tree, state: state)
        XCTAssertEqual(plan.bars.map(\.title), ["Review the onboarding flow"])
        XCTAssertEqual(plan.blocks.map(\.title), ["A walk before the first meeting"])
        XCTAssertEqual(plan.lanes, 1)
    }

    func testEntriesKeepTheirMomentsBesideTheirDays() throws {
        let entry = try XCTUnwrap(entries(world()).first { $0.title == "Pick a name" })
        XCTAssertEqual(entry.when, at(2026, 11, 3))
        XCTAssertEqual(entry.whenAt, at(2026, 11, 3, 14, 0))
        XCTAssertEqual(entry.due, at(2026, 11, 3))
        XCTAssertEqual(entry.dueAt, at(2026, 11, 3, 14, 30))
    }
}
