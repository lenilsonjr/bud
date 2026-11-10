import Foundation

/// One month as the year draws it: the name and six rows of seven cells from `CalendarMonth`,
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
        let today = calendar.startOfDay(for: now)
        let thisMonth = YearMonth(containing: now, calendar: calendar)
        let gridStart = range.start(calendar: calendar)
        let gridLast = calendar.date(byAdding: .day, value: -1, to: range.end(calendar: calendar)) ?? gridStart

        // The long buds, longest first, each writing its tone on every day it crosses inside
        // the grid: a shorter one crossing the same day writes last and shows.
        let shown = entries.filter(state.shows)
        let spans = CalendarSpan.list(in: shown, state: state)
        var shade: [Date: ThreadTone] = [:]
        for span in spans {
            var day = max(span.start, gridStart)
            let stop = min(span.end, gridLast)
            while day <= stop {
                shade[day] = span.entry.tone
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? stop.addingTimeInterval(1)
            }
        }
        // The dots: a long bud on the day it is due, a bud with one day on that day; the first
        // bud in reading order keeps the day.
        let spanned = Dictionary(spans.map { ($0.entry.id, $0) }, uniquingKeysWith: { a, _ in a })
        var dots: [Date: ThreadTone] = [:]
        for entry in shown {
            let day: Date
            if spanned[entry.id] != nil {
                guard let due = entry.due, state.shows(.due) else { continue }
                day = due
            } else {
                guard let first = state.dates(of: entry).first else { continue }
                day = first
            }
            if dots[day] == nil { dots[day] = entry.tone }
        }

        let lattices = range.all.map { CalendarMonth(containing: $0.start(calendar: calendar), now: now, calendar: calendar) }
        weekdays = (lattices.first?.weekdays ?? []).map { String($0.prefix(1)) }
        months = zip(range.all, lattices).map { month, lattice in
            SmallMonth(
                month: month,
                title: month.text("MMMM", calendar: calendar),
                weeks: lattice.weeks.map { week in
                    week.map { day in
                        guard day.inMonth else { return nil }
                        return SmallMonth.Day(
                            date: day.date, number: day.number, isToday: day.isToday, isPast: day.date < today,
                            shade: shade[day.date], dot: dots[day.date]
                        )
                    }
                },
                isCurrent: month == thisMonth,
                isPast: month < thisMonth
            )
        }
    }

    /// The months in rows of four, the last row shorter when they do not divide.
    public var rows: [[SmallMonth]] {
        stride(from: 0, to: months.count, by: Self.columns).map { Array(months[$0..<min($0 + Self.columns, months.count)]) }
    }

    public func month(_ month: YearMonth) -> SmallMonth? { months.first { $0.month == month } }
}
