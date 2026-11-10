import Foundation

/// One month as the grid draws it: six rows of seven days from the first day of the week the
/// month starts in, so every month is the same height and the days before and after it show
/// greyed. Pure, so a test reads it on any platform.
public struct CalendarMonth: Equatable, Sendable {
    public struct Day: Hashable, Sendable {
        /// Midnight at the start of the day, in the calendar's zone.
        public let date: Date
        public let number: Int
        /// False for the days before and after the month that fill the first and last rows.
        public let inMonth: Bool
        public let isToday: Bool
        public let isWeekend: Bool
    }

    public static let rows = 6
    public static let columns = 7

    /// "November 2026".
    public let title: String
    /// "MON" to "SUN", from the calendar's first weekday.
    public let weekdays: [String]
    /// Six rows of seven days, the first row starting at the calendar's first weekday.
    public let weeks: [[Day]]
    /// Midnight of the month's first day.
    public let start: Date
    public let calendar: Calendar

    /// The month holding `date`, with `now` marking today.
    public init(containing date: Date, now: Date, calendar: Calendar = .current) {
        self.calendar = calendar
        let parts = calendar.dateComponents([.year, .month], from: date)
        let first = calendar.date(from: parts) ?? calendar.startOfDay(for: date)
        start = calendar.startOfDay(for: first)
        title = CalendarRange.month.title(for: first, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let month = parts.month
        // The first cell: the start of the week the month opens in.
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -offset, to: start) ?? start
        var weeks: [[Day]] = []
        for row in 0..<Self.rows {
            var week: [Day] = []
            for column in 0..<Self.columns {
                let day = calendar.date(byAdding: .day, value: row * Self.columns + column, to: gridStart) ?? gridStart
                week.append(Day(
                    date: day,
                    number: calendar.component(.day, from: day),
                    inMonth: calendar.component(.month, from: day) == month,
                    isToday: day == today,
                    isWeekend: calendar.isDateInWeekend(day)
                ))
            }
            weeks.append(week)
        }
        self.weeks = weeks
        let symbols = calendar.shortWeekdaySymbols
        weekdays = (0..<Self.columns).map { symbols[(calendar.firstWeekday - 1 + $0) % 7].uppercased() }
    }

    /// The first day in the grid and the day after the last: what a bar can be clipped to.
    public var gridStart: Date { weeks[0][0].date }
    public var gridEnd: Date { calendar.date(byAdding: .day, value: 1, to: weeks[Self.rows - 1][Self.columns - 1].date) ?? gridStart }

    /// Where a day sits in the grid, or nil when it is outside it.
    public func cell(of date: Date) -> (row: Int, column: Int)? {
        let day = calendar.startOfDay(for: date)
        guard day >= gridStart, day < gridEnd else { return nil }
        let index = calendar.dateComponents([.day], from: gridStart, to: day).day ?? 0
        return (index / Self.columns, index % Self.columns)
    }

    /// The month before or after this one, keeping `now`.
    public func shifted(by months: Int, now: Date) -> CalendarMonth {
        let date = calendar.date(byAdding: .month, value: months, to: start) ?? start
        return CalendarMonth(containing: date, now: now, calendar: calendar)
    }
}
