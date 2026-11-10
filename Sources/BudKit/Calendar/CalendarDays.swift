import Foundation

/// A run of days with their hours, as the Day and Week views draw them: one day, or the seven
/// of a week. The all-day row on top holds the buds with no time of day and the bars of buds
/// that span days; the hours below hold the buds with a time of day, from 07:00, with the now
/// line where the clock is. Pure, so a test reads it on any platform.
///
/// A moment counts as timed when it is not midnight in the calendar's zone: a day picked in a
/// vault file (`when: 2026-11-09`) is all-day, a calendar event's start is timed. A bud whose
/// scheduled and due moments fall on the same day is one block from the first to the second;
/// one with a moment only, or a due moment with no time, takes half an hour.
public struct CalendarDays: Equatable, Sendable {
    public struct Day: Hashable, Sendable {
        /// Midnight at the start of the day, in the calendar's zone.
        public let date: Date
        public let number: Int
        /// "MON".
        public let weekday: String
        public let isToday: Bool
        public let isWeekend: Bool
    }

    /// A bud in the all-day row: a span across columns, or one day with no time.
    public struct Bar: Hashable, Identifiable, Sendable {
        public let entry: UUID
        public let title: String
        /// What the bar reads: "Apartment hunt · day 1 of 22, due 30 Nov" over one day,
        /// "Apartment hunt → 30 Nov" when it runs past the week, "Ship v1.2 · due 4 Dec" when it
        /// ends in it, the title alone for one day with no time.
        public let label: String
        public let tone: ThreadTone
        /// The first and last column it covers, inclusive.
        public let from: Int
        public let to: Int
        /// Which lane of the row it takes, 0 at the top.
        public let lane: Int
        /// True where the bud's scheduled day is in the run: the bar draws an arrow.
        public let starts: Bool
        /// True where the due day is in the run: the bar draws a flag.
        public let ends: Bool
        public let isDone: Bool

        public var id: UUID { entry }
        public var columns: Int { to - from + 1 }
    }

    /// A bud in the hours: its column, its minutes from midnight, and its share of the column
    /// where blocks overlap.
    public struct Block: Hashable, Identifiable, Sendable {
        public let entry: UUID
        public let title: String
        public let tone: ThreadTone
        public let column: Int
        /// Minutes from midnight where the block starts and ends.
        public let start: Int
        public let end: Int
        /// "07:00–07:45" when the bud has both moments on the day; "15:00" when it has one.
        public let time: String
        /// Which of `lanes` side by side it takes, 0 at the left, where blocks overlap.
        public let lane: Int
        public let lanes: Int
        public let isDone: Bool
        /// True when the moment placed is the due one, false for the scheduled one.
        public let isDue: Bool

        public var id: String { "\(entry)-\(isDue ? "due" : "when")" }
    }

    /// Where the clock is: today's column and the minutes from midnight.
    public struct NowMark: Hashable, Sendable {
        public let column: Int
        public let minutes: Int
    }

    /// The hours shown when nothing falls outside them: 07:00 to 21:00.
    public static let firstHourShown = 7
    public static let lastHourShown = 21
    /// What a block with no end takes, in minutes.
    public static let blockLength = 30

    public let days: [Day]
    public let bars: [Bar]
    /// How many lanes the all-day row takes.
    public let lanes: Int
    public let blocks: [Block]
    /// The hours drawn, `firstHour` to `lastHour`: 07:00 to 21:00, stretched to hold a block
    /// earlier or later.
    public let firstHour: Int
    public let lastHour: Int
    /// The now line, when the clock is on one of the days and within the hours.
    public let now: NowMark?
    public let calendar: Calendar

    /// The day holding `date`.
    public static func day(containing date: Date, now: Date, entries: [CalendarEntry], state: CalendarState, calendar: Calendar = .current) -> CalendarDays {
        CalendarDays(from: calendar.startOfDay(for: date), days: 1, now: now, entries: entries, state: state, calendar: calendar)
    }

    /// The week holding `date`, from the calendar's first weekday.
    public static func week(containing date: Date, now: Date, entries: [CalendarEntry], state: CalendarState, calendar: Calendar = .current) -> CalendarDays {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        return CalendarDays(from: calendar.startOfDay(for: start), days: 7, now: now, entries: entries, state: state, calendar: calendar)
    }

    /// `count` days from the one holding `start`, with the entries the state shows placed.
    public init(from start: Date, days count: Int, now: Date, entries: [CalendarEntry], state: CalendarState, calendar: Calendar = .current) {
        self.calendar = calendar
        let count = max(1, count)
        let first = calendar.startOfDay(for: start)
        let today = calendar.startOfDay(for: now)
        let symbols = calendar.shortWeekdaySymbols
        var days: [Day] = []
        for index in 0..<count {
            let date = calendar.date(byAdding: .day, value: index, to: first) ?? first
            days.append(Day(
                date: date,
                number: calendar.component(.day, from: date),
                weekday: symbols[(calendar.component(.weekday, from: date) - 1 + 7) % 7].uppercased(),
                isToday: date == today,
                isWeekend: calendar.isDateInWeekend(date)
            ))
        }
        self.days = days
        let last = days[count - 1].date
        func column(of day: Date) -> Int? {
            guard day >= first, day <= last else { return nil }
            return calendar.dateComponents([.day], from: first, to: day).day
        }
        func daysBetween(_ a: Date, _ b: Date) -> Int { calendar.dateComponents([.day], from: a, to: b).day ?? 0 }

        // The all-day row: spans first, longest first then by start, so the long ones keep the
        // top lanes; then the one-day buds by column.
        let shown = entries.filter(state.shows)
        struct Lying { let entry: CalendarEntry; let start: Date; let end: Date; let span: Bool }
        var lying: [Lying] = []
        var timed: [Block] = []
        for entry in shown {
            let dates = state.dates(of: entry)
            guard let earliest = dates.min(), let latest = dates.max() else { continue }
            if earliest < latest {
                lying.append(Lying(entry: entry, start: earliest, end: latest, span: true))
                continue
            }
            // One day, or both moments on it: the due day wins the flag; the scheduled moment
            // places the block, the due moment ends it, or places it when there is none.
            let day = earliest
            let whenAt = state.shows(.when) ? entry.whenAt : nil
            let dueAt = state.shows(.due) ? entry.dueAt : nil
            let timedWhen = whenAt.flatMap { Self.isTimed($0, calendar: calendar) ? $0 : nil }
            let timedDue = dueAt.flatMap { Self.isTimed($0, calendar: calendar) ? $0 : nil }
            guard let startAt = timedWhen ?? timedDue else {
                lying.append(Lying(entry: entry, start: day, end: day, span: false))
                continue
            }
            guard let column = column(of: day) else { continue }
            let startMinutes = Self.minutes(of: startAt, calendar: calendar)
            let ending = timedWhen != nil ? timedDue.map { Self.minutes(of: $0, calendar: calendar) } : nil
            let endMinutes = ending.flatMap { $0 > startMinutes ? $0 : nil }
            let isDue = state.shows(.due) && entry.due == day && timedWhen == nil
            timed.append(Block(
                entry: entry.id, title: entry.title, tone: entry.tone, column: column,
                start: startMinutes, end: endMinutes ?? startMinutes + Self.blockLength,
                time: endMinutes.map { "\(Self.time(startMinutes))–\(Self.time($0))" } ?? Self.time(startMinutes),
                lane: 0, lanes: 1, isDone: entry.isDone, isDue: isDue
            ))
        }
        lying.sort { a, b in
            if a.span != b.span { return a.span }
            let (la, lb) = (daysBetween(a.start, a.end), daysBetween(b.start, b.end))
            if la != lb { return la > lb }
            return (a.start, a.entry.title) < (b.start, b.entry.title)
        }
        var bars: [Bar] = []
        var taken: [[ClosedRange<Int>]] = []
        for item in lying {
            let head = max(item.start, first)
            let tail = min(item.end, last)
            guard head <= tail, let from = column(of: head), let to = column(of: tail) else { continue }
            var lane = 0
            while taken.indices.contains(lane) && taken[lane].contains(where: { $0.overlaps(from...to) }) { lane += 1 }
            if lane == taken.count { taken.append([]) }
            taken[lane].append(from...to)
            let entry = item.entry
            let starts = entry.when.map { column(of: $0) != nil } ?? false
            let ends = entry.due.map { column(of: $0) != nil } ?? false
            let label: String
            if !item.span {
                label = entry.title
            } else if let due = entry.due, count == 1 {
                label = "\(entry.title) · day \(daysBetween(item.start, first) + 1) of \(daysBetween(item.start, item.end) + 1), due \(DayText.short(due, calendar: calendar))"
            } else if let due = entry.due, due > last {
                label = "\(entry.title) → \(DayText.short(due, calendar: calendar))"
            } else if let due = entry.due, ends {
                label = "\(entry.title) · due \(DayText.short(due, calendar: calendar))"
            } else {
                label = entry.title
            }
            bars.append(Bar(
                entry: entry.id, title: entry.title, label: label, tone: entry.tone, from: from, to: to, lane: lane,
                starts: starts, ends: ends, isDone: entry.isDone
            ))
        }
        self.bars = bars
        lanes = taken.count

        // The hours: blocks that overlap in a column share it side by side, each cluster of
        // overlapping blocks splitting the width between its lanes.
        var blocks: [Block] = []
        for column in 0..<count {
            let inColumn = timed.filter { $0.column == column }.sorted { ($0.start, $0.end, $0.title) < ($1.start, $1.end, $1.title) }
            var cluster: [(block: Block, lane: Int)] = []
            var laneEnds: [Int] = []
            var clusterEnd = Int.min
            func flush() {
                for (block, lane) in cluster {
                    blocks.append(Block(
                        entry: block.entry, title: block.title, tone: block.tone, column: block.column, start: block.start, end: block.end,
                        time: block.time, lane: lane, lanes: laneEnds.count, isDone: block.isDone, isDue: block.isDue
                    ))
                }
                cluster = []
                laneEnds = []
            }
            for block in inColumn {
                if !cluster.isEmpty, block.start >= clusterEnd { flush() }
                let lane = laneEnds.firstIndex { $0 <= block.start } ?? laneEnds.count
                if lane == laneEnds.count { laneEnds.append(block.end) } else { laneEnds[lane] = block.end }
                cluster.append((block, lane))
                clusterEnd = max(clusterEnd, block.end)
            }
            flush()
        }
        self.blocks = blocks
        let earliest = blocks.map(\.start).min() ?? Self.firstHourShown * 60
        let latest = blocks.map(\.end).max() ?? Self.lastHourShown * 60
        firstHour = max(0, min(Self.firstHourShown, earliest / 60))
        lastHour = min(24, max(Self.lastHourShown, (latest + 59) / 60))

        let minutes = Self.minutes(of: now, calendar: calendar)
        if let column = column(of: today), minutes >= firstHour * 60, minutes <= lastHour * 60 {
            self.now = NowMark(column: column, minutes: minutes)
        } else {
            self.now = nil
        }
    }

    /// The hour labels down the left, "07:00" to the last hour but one: the last line has no
    /// room under it.
    public var hours: [String] { (firstHour..<lastHour).map { Self.time($0 * 60) } }
    public var hourCount: Int { lastHour - firstHour }

    /// Where a minute of the day sits down the hours: 0 at the first hour's line, 1 at the last.
    public func position(ofMinutes minutes: Int) -> Double {
        let span = Double(max(1, hourCount * 60))
        return Double(minutes - firstHour * 60) / span
    }

    public func blocks(in column: Int) -> [Block] { blocks.filter { $0.column == column } }

    /// True when the moment is not midnight in the calendar's zone.
    public static func isTimed(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: date) != date
    }

    /// Minutes from the day's midnight.
    public static func minutes(of date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// "07:00" for minutes from midnight: the board's clock, the same on every platform.
    public static func time(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

#if canImport(SwiftUI)
extension BudStore {
    /// The day on show with its buds placed, after the threads and switches.
    public var dayPlan: CalendarDays {
        CalendarDays.day(containing: calendarFocus, now: now, entries: CalendarEntry.all(in: tree, calendar: calendar), state: calendarState, calendar: calendar)
    }

    /// The week on show with its buds placed.
    public var weekPlan: CalendarDays {
        CalendarDays.week(containing: calendarFocus, now: now, entries: CalendarEntry.all(in: tree, calendar: calendar), state: calendarState, calendar: calendar)
    }
}
#endif
