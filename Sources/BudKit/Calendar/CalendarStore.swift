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

    /// Moves one of a bud's days onto `day`, keeping its time of day, and offers to move it
    /// back. Only that key reaches the file: `when` or `due`, nothing else. The one step every
    /// drag on a calendar ends in, whichever view it was dragged in; a drop on the day it is
    /// already on changes nothing and says nothing. A routine shown on its stamped day has no
    /// `when` of its own: dragging it gives it one, and Undo takes it away again.
    public func moveDate(_ key: DateKey, of id: UUID, to day: Date) {
        guard let bud = tree.bud(id) else { return }
        // What the file carries, which Undo puts back: nil for a routine on its stamped day.
        let kept = key == .when ? bud.when : bud.due
        let stamped = key == .when && bud.when == nil ? bud.from.flatMap(Tree.stampOccurrence) : nil
        guard let old = kept ?? stamped else { return }
        let new = key.moved(old, toDay: day, calendar: calendar)
        guard calendar.startOfDay(for: new) != calendar.startOfDay(for: old) else { return }
        set(key, of: id, to: new)
        let label = DayText.short(new, calendar: calendar)
        let message = key == .when ? "Scheduled \(bud.text) for \(label)" : "Made \(bud.text) due \(label)"
        toasts.show(Undoable(message: message, systemImage: key == .when ? "calendar" : "flag") { [weak self] in
            Task { @MainActor in self?.set(key, of: id, to: kept) }
        })
    }

    /// The one day's write, here and in the vault, without a toast.
    private func set(_ key: DateKey, of id: UUID, to date: Date?) {
        switch key {
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
