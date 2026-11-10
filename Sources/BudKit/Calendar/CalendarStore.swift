import Foundation

// MARK: the calendar

#if canImport(SwiftUI)
extension BudStore {
    /// The threads the left column lists, coloured in turn.
    public var calendarThreads: [CalendarThread] { CalendarThread.list(in: tree) }

    /// The day the calendar looks at: the one it was moved to, or today.
    public var calendarFocus: Date { calendarDate ?? now }

    /// The month on show with its buds placed, after the threads and switches. Built from one
    /// walk of the tree; a view reads it once a render.
    public var monthGrid: MonthGrid {
        let month = CalendarMonth(containing: calendarFocus, now: now, calendar: calendar)
        return MonthGrid(month: month, entries: CalendarEntry.all(in: tree, calendar: calendar), state: calendarState)
    }

    /// Shows or hides a thread's buds at once.
    public func toggleThread(_ id: UUID) { calendarState.toggle(thread: id) }

    /// Turns a Show switch over at once.
    public func toggle(_ show: CalendarShow) { calendarState.toggle(show) }

    /// Moves the calendar back or forward by its range: a day, a week, a month, a quarter or a
    /// year at a time, or a custom range's own months.
    public func shiftCalendar(by steps: Int) {
        calendarDate = calendarState.range.shift(calendarFocus, by: steps, custom: customRange, calendar: calendar)
    }

    /// Back to today.
    public func calendarToday() { calendarDate = nil }
}
#endif
