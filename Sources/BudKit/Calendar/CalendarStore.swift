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
    public var monthGrid: MonthGrid { monthGrid(moving: nil) }

    /// The month as it would stand with a drag dropped where it is: the bud in hand drawn with
    /// its day on the one under the pointer, so the bar stretches or the item moves as the
    /// pointer crosses the cells. The month itself with no drag.
    public func monthGrid(moving drag: CalendarDrag?) -> MonthGrid {
        let month = CalendarMonth(containing: calendarFocus, now: now, calendar: calendar)
        let entries = CalendarEntry.all(in: tree, calendar: calendar).moving(drag, calendar: calendar)
        return MonthGrid(month: month, entries: entries, state: calendarState)
    }

    /// Moves one of a bud's days onto `day`, keeping its time of day, and offers to move it
    /// back. Only that key reaches the file: `when` or `due`, nothing else. The one step every
    /// drag on a calendar ends in, whichever view it was dragged in; a drop on the day it is
    /// already on changes nothing and says nothing.
    public func moveDate(_ field: DateKey, of id: UUID, to day: Date) {
        guard let bud = tree.bud(id), let old = field == .when ? bud.when : bud.due else { return }
        let new = field.moved(old, toDay: day, calendar: calendar)
        guard calendar.startOfDay(for: new) != calendar.startOfDay(for: old) else { return }
        set(field, of: id, to: new)
        let label = DayText.day(new, calendar: calendar)
        let message = field == .when ? "Scheduled \(bud.text) for \(label)" : "Made \(bud.text) due \(label)"
        toasts.show(Undoable(message: message, systemImage: field == .when ? "calendar" : "flag") { [weak self] in
            Task { @MainActor in self?.set(field, of: id, to: old) }
        })
    }

    /// A bar's leading edge let go on a day.
    public func moveWhen(of id: UUID, to day: Date) { moveDate(.when, of: id, to: day) }

    /// A bar's trailing edge let go on a day.
    public func moveDue(of id: UUID, to day: Date) { moveDate(.due, of: id, to: day) }

    /// The one day's write, here and in the vault, without a toast.
    private func set(_ field: DateKey, of id: UUID, to date: Date?) {
        switch field {
        case .when: setWhen(id, date)
        case .due: setDue(id, date)
        }
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
