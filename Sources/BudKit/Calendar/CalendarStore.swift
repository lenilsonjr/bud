import Foundation

// MARK: the calendar

#if canImport(SwiftUI)
extension BudStore {
    /// The threads the left column lists, coloured in turn.
    public var calendarThreads: [CalendarThread] { CalendarThread.list(in: tree) }

    /// The day the calendar looks at: the one it was moved to, or today.
    public var calendarFocus: Date { calendarDate ?? now }

    /// The month on show with its buds placed, after the threads and switches.
    public var monthGrid: MonthGrid {
        let month = CalendarMonth(containing: calendarFocus, now: now, calendar: dateCalendar)
        return MonthGrid(month: month, entries: CalendarEntry.all(in: tree, calendar: dateCalendar), state: calendar)
    }

    /// Shows or hides a thread's buds at once.
    public func toggleThread(_ id: UUID) { calendar.toggle(thread: id) }

    /// Turns a Show switch over at once.
    public func toggle(_ show: CalendarShow) { calendar.toggle(show) }

    /// Moves the calendar a month back or forward.
    public func shiftCalendar(months: Int) {
        let month = CalendarMonth(containing: calendarFocus, now: now, calendar: dateCalendar)
        calendarDate = month.shifted(by: months, now: now).start
    }

    /// Back to today.
    public func calendarToday() { calendarDate = nil }
}
#endif
