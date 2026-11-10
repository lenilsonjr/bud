import Foundation

/// The timeline: the range as one axis of days, a column on the scale for each day, week or
/// month the range asks for, and one row per bud grouped under its thread. A bud with two days
/// is a bar from one to the other, drawn flat at an edge it runs past; a bud with one day is a
/// point. A thread folds to its header, which keeps a rail over the days its buds cover. Pure,
/// so a test reads it on any platform.
public struct Timeline: Equatable, Sendable {
    /// What one column of the scale is: a day for the month, a week for the quarter, a month
    /// for the year.
    public enum Unit: Equatable, Sendable {
        case day, week, month

        /// The unit a range draws its columns in; nil while the range has no timeline.
        public init?(range: CalendarRange) {
            switch range {
            case .month: self = .day
            case .quarter: self = .week
            case .year: self = .month
            case .day, .week, .custom: return nil
            }
        }

        /// The label over a column: "9", "9 Nov", "Nov". Written out, so it reads the same on
        /// every platform.
        var format: String {
            switch self {
            case .day: return "d"
            case .week: return "d MMM"
            case .month: return "MMM"
            }
        }

        /// About how many days a column spans: what a label's room is measured against.
        public var days: Int {
            switch self {
            case .day: return 1
            case .week: return 7
            case .month: return 30
            }
        }
    }

    /// One tick of the scale: the day it starts on, counted from the range's first day, and the
    /// label beside it.
    public struct Column: Hashable, Sendable {
        public let day: Int
        public let label: String
        /// True for the column holding today: its label draws in the leaf, bold.
        public let isToday: Bool
    }

    /// One bud's row: where it sits on the axis and how it draws.
    public struct Row: Hashable, Identifiable, Sendable {
        public let id: UUID
        public let title: String
        public let tone: ThreadTone
        /// The first and last day it covers, counted from the range's first day, inclusive, and
        /// clipped to the range. The same day for a point.
        public let from: Int
        public let to: Int
        /// How many days the bud spans in all, past the range's edges too: what a reader is told.
        public let days: Int
        /// One date, or both dates on one day: a point on its day instead of a bar.
        public let isPoint: Bool
        /// The bar runs on past the range's first day: its start draws flat.
        public let startsBefore: Bool
        /// The bar runs on past the range's last day: its end draws flat.
        public let endsAfter: Bool
        public let isDone: Bool
        public let isRoutine: Bool
        /// For a point, true when the day shown is the due day.
        public let isDue: Bool
    }

    /// A thread with its rows, in reading order.
    public struct Thread: Hashable, Identifiable, Sendable {
        public let id: UUID
        public let title: String
        public let tone: ThreadTone
        /// Folded to its header. The rows are kept, so the rail still spans them.
        public let isCollapsed: Bool
        public let rows: [Row]
        /// The first and last day its rows cover: the rail under its header.
        public let from: Int
        public let to: Int

        /// The rows drawn under the header: none while folded.
        public var shownRows: [Row] { isCollapsed ? [] : rows }
    }

    public let unit: Unit
    /// How many days the axis holds: every position is a count of days from the first.
    public let days: Int
    public let columns: [Column]
    /// Days drawn in the quiet shade: the weekends by the day, each month's first day by the
    /// week, none by the month.
    public let shaded: [ClosedRange<Int>]
    /// Today's day on the axis, or nil when today is outside the range.
    public let today: Int?
    /// The threads with a bud in the range, in their order; hidden threads are left out.
    public let threads: [Thread]

    /// The timeline of `range` around `date`, or nil while the range has no timeline.
    public init?(range: CalendarRange, containing date: Date, now: Date, entries: [CalendarEntry], threads: [CalendarThread], state: CalendarState, calendar: Calendar = .current) {
        guard let unit = Unit(range: range) else { return nil }
        self.unit = unit
        let span = range.interval(containing: date, calendar: calendar)
        let days = max(1, calendar.dateComponents([.day], from: span.start, to: span.end).day ?? 1)
        self.days = days
        func day(of date: Date) -> Int {
            calendar.dateComponents([.day], from: span.start, to: calendar.startOfDay(for: date)).day ?? 0
        }
        func at(_ day: Int) -> Date {
            calendar.date(byAdding: .day, value: day, to: span.start) ?? span.start
        }
        let todayDay = day(of: now)
        today = (0..<days).contains(todayDay) ? todayDay : nil

        // The scale: a tick on every day, on every week's first day, or on every month's first.
        let formatter = DayText.formatter(format: unit.format, calendar: calendar)
        var columns: [Column] = []
        var shaded: [ClosedRange<Int>] = []
        let monthStarts = calendar.monthStarts(in: span).map(day(of:))
        switch unit {
        case .day:
            for d in 0..<days {
                let date = at(d)
                columns.append(Column(day: d, label: formatter.string(from: date), isToday: d == todayDay))
                if calendar.isDateInWeekend(date) {
                    if let last = shaded.last, last.upperBound == d - 1 {
                        shaded[shaded.count - 1] = last.lowerBound...d
                    } else {
                        shaded.append(d...d)
                    }
                }
            }
        case .week:
            // The first column is the range's first day even when it is not a week's first,
            // so the days before the first full week have their label and their today.
            var starts = [0]
            var d = (7 - calendar.daysIntoWeek(of: span.start)) % 7
            while d < days {
                if d > 0 { starts.append(d) }
                d += 7
            }
            for (i, start) in starts.enumerated() {
                let next = i + 1 < starts.count ? starts[i + 1] : days
                columns.append(Column(day: start, label: formatter.string(from: at(start)), isToday: (start..<next).contains(todayDay)))
            }
            shaded = monthStarts.map { $0...$0 }
        case .month:
            for (i, start) in monthStarts.enumerated() {
                let next = i + 1 < monthStarts.count ? monthStarts[i + 1] : days
                columns.append(Column(day: start, label: formatter.string(from: at(start)), isToday: (start..<next).contains(todayDay)))
            }
        }
        self.columns = columns
        self.shaded = shaded

        // One row per bud the switches show, under its thread; a thread with no bud in the range
        // is left out.
        var rows: [UUID: [Row]] = [:]
        for entry in entries where state.shows(entry) {
            let dates = state.dates(of: entry)
            guard let first = dates.min(), let last = dates.max() else { continue }
            let firstDay = day(of: first)
            let lastDay = day(of: last)
            guard lastDay >= 0, firstDay < days else { continue }
            let point = firstDay == lastDay
            rows[entry.thread, default: []].append(Row(
                id: entry.id, title: entry.title, tone: entry.tone,
                from: max(firstDay, 0), to: min(lastDay, days - 1),
                days: lastDay - firstDay + 1,
                isPoint: point,
                startsBefore: !point && firstDay < 0,
                endsAfter: !point && lastDay >= days,
                isDone: entry.isDone, isRoutine: entry.isRoutine,
                isDue: point && state.shows(.due) && entry.due == first
            ))
        }
        self.threads = threads.compactMap { thread in
            guard let rows = rows[thread.id], !rows.isEmpty else { return nil }
            return Thread(
                id: thread.id, title: thread.title, tone: thread.tone,
                isCollapsed: state.isCollapsed(thread: thread.id),
                rows: rows,
                from: rows.map(\.from).min() ?? 0,
                to: rows.map(\.to).max() ?? 0
            )
        }
    }

    /// Where a day starts along the axis, as a share of its width: 0 at the first day, 1 after
    /// the last.
    public func position(ofDay day: Int) -> Double {
        Double(day) / Double(days)
    }
}
