import Foundation

// MARK: the timeline

#if canImport(SwiftUI)
extension BudStore {
    /// The timeline of the range on show, with its buds placed under their threads; nil while the
    /// range has no timeline. Built from one walk of the tree; a view reads it once a render.
    public var timeline: Timeline? {
        Timeline(
            range: calendarState.range, containing: calendarFocus, now: now,
            entries: CalendarEntry.all(in: tree, calendar: calendar), threads: calendarThreads,
            state: calendarState, calendar: calendar
        )
    }

    /// The line under the title, when the range has one.
    public var calendarSubtitle: String? {
        calendarState.range.subtitle(for: calendarFocus, calendar: calendar)
    }

    /// Folds a thread's rows up under its header in the timeline, or opens them again. Kept on
    /// this device with the rest of the calendar's state.
    public func toggleCollapsed(_ id: UUID) { calendarState.toggle(collapsed: id) }
}
#endif
