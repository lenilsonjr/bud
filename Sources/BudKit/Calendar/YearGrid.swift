import Foundation

/// One month as the year draws it: the name, the weekday letters, six rows of seven cells with
/// the days before and after the month left empty, each day shaded by the long bud crossing it
/// and dotted by a bud on it. Pure, so a test reads it on any platform.
public struct SmallMonth: Equatable, Sendable {
    public struct Day: Hashable, Sendable {
        /// Midnight at the start of the day, in the calendar's zone.
        public let date: Date
        public let number: Int
        public let isToday: Bool
        /// Before today: drawn dim.
        public let isPast: Bool
        /// The soft fill of a long bud crossing the day: the shortest one when several do, so a
        /// short bud is not lost inside a long one.
        public let shade: ThreadTone?
        /// The dot under the number: a bud on this day, or a long bud due on it. The first in
        /// reading order when there are more.
        public let dot: ThreadTone?
    }

    public let month: YearMonth
    /// "January".
    public let title: String
    /// Six rows of seven, nil where the row runs outside the month.
    public let weeks: [[Day?]]
    /// Today's month: its name in the leaf.
    public let isCurrent: Bool
    /// Before today's month: its name dim.
    public let isPast: Bool

    /// The days in the month, in order.
    public var days: [Day] { weeks.flatMap { $0 }.compactMap { $0 } }

    public func day(_ number: Int) -> Day? { days.first { $0.number == number } }
}

/// Twelve small months for a year, or the months of a custom range, laid out in rows of four.
/// The buds are placed once for every month from one list of entries.
public struct YearGrid: Equatable, Sendable {
    public static let columns = 4

    public let months: [SmallMonth]
    /// "M" to "S", from the calendar's first weekday, over every month.
    public let weekdays: [String]

    /// The twelve months of `year`.
    public init(year: Int, entries: [CalendarEntry], state: CalendarState, now: Date, calendar: Calendar = .current) {
        self.init(range: CustomRange(from: YearMonth(year: year, month: 1), months: 12), entries: entries, state: state, now: now, calendar: calendar)
    }

    /// The months of a custom range.
    public init(range: CustomRange, entries: [CalendarEntry], state: CalendarState, now: Date, calendar: Calendar = .current) {
        let symbols = calendar.shortWeekdaySymbols
        weekdays = (0..<CalendarMonth.columns).map { String(symbols[(calendar.firstWeekday - 1 + $0) % 7].prefix(1)).uppercased() }
        let today = calendar.startOfDay(for: now)
        let thisMonth = YearMonth(containing: now, calendar: calendar)
        let gridStart = range.start(calendar: calendar)
        let gridEnd = range.end(calendar: calendar)

        // The long buds, longest first, each writing its tone on every day it crosses inside
        // the grid: a shorter one crossing the same day writes last and shows.
        let shown = entries.filter(state.shows)
        var shade: [Date: ThreadTone] = [:]
        let spans: [(entry: CalendarEntry, start: Date, end: Date)] = shown.compactMap { entry in
            let dates = state.dates(of: entry)
            guard let start = dates.min(), let end = dates.max(), start < end else { return nil }
            return (entry, start, end)
        }.sorted { a, b in
            let la = a.end.timeIntervalSince(a.start), lb = b.end.timeIntervalSince(b.start)
            if la != lb { return la > lb }
            return (a.start, a.entry.title) < (b.start, b.entry.title)
        }
        for span in spans {
            var day = max(span.start, gridStart)
            let last = min(span.end, gridEnd)
            while day <= last, day < gridEnd {
                shade[day] = span.entry.tone
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? gridEnd
            }
        }
        // The dots: a bud on one day, or a long bud on the day it is due; the first bud in
        // reading order keeps the day.
        var dots: [Date: ThreadTone] = [:]
        for entry in shown {
            let dates = state.dates(of: entry)
            guard let start = dates.min(), let end = dates.max() else { continue }
            let day: Date
            if start == end {
                day = start
            } else if let due = entry.due, state.shows(.due) {
                day = due
            } else {
                continue
            }
            if dots[day] == nil { dots[day] = entry.tone }
        }

        months = range.all.map { month in
            let start = month.start(calendar: calendar)
            let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
            let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
            var weeks: [[SmallMonth.Day?]] = []
            for row in 0..<CalendarMonth.rows {
                weeks.append((0..<CalendarMonth.columns).map { column in
                    let number = row * CalendarMonth.columns + column - offset + 1
                    guard number >= 1, number <= count else { return nil }
                    let date = calendar.date(byAdding: .day, value: number - 1, to: start) ?? start
                    return SmallMonth.Day(
                        date: date, number: number, isToday: date == today, isPast: date < today,
                        shade: shade[date], dot: dots[date]
                    )
                })
            }
            return SmallMonth(
                month: month, title: month.text("MMMM", calendar: calendar), weeks: weeks,
                isCurrent: month == thisMonth, isPast: month < thisMonth
            )
        }
    }

    /// The months in rows of four, the last row shorter when they do not divide.
    public var rows: [[SmallMonth]] {
        stride(from: 0, to: months.count, by: Self.columns).map { Array(months[$0..<min($0 + Self.columns, months.count)]) }
    }

    public func month(_ month: YearMonth) -> SmallMonth? { months.first { $0.month == month } }
}
