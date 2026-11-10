import Foundation

// MARK: the year and the custom range

#if canImport(SwiftUI)
extension BudStore {
    /// The custom range on show: the state's months from the month the calendar looks at. The
    /// date is the one source, as for every range: Today brings it back to this month, the
    /// chevrons move it by the length, and the picker sets it to the first month picked.
    public var customRange: CustomRange {
        CustomRange(from: YearMonth(containing: calendarFocus, calendar: calendar), months: calendarState.customMonths)
    }

    /// The title over the grid: the range's for the day it looks at, or the custom range's own.
    public var calendarTitle: String {
        calendarState.range.title(for: calendarFocus, custom: customRange, calendar: calendar)
    }

    /// The year on show, or the custom range's months, as small months with their buds. Built
    /// from one walk of the tree; a view reads it once a render.
    public var yearGrid: YearGrid {
        let entries = CalendarEntry.all(in: tree, calendar: calendar)
        if calendarState.range == .custom {
            return YearGrid(range: customRange, entries: entries, state: calendarState, now: now, calendar: calendar)
        }
        return YearGrid(year: calendar.component(.year, from: calendarFocus), entries: entries, state: calendarState, now: now, calendar: calendar)
    }

    /// The picker's presets: the two fixed ones and one for each thread with a due day ahead.
    public var rangePresets: [RangePreset] {
        RangePreset.all(now: now, threads: tree.children(of: rootID).map { ($0.id, $0.text, $0.due) }, calendar: calendar)
    }

    /// Shows a custom range: the calendar looks at its first month, the state keeps its length,
    /// and the Custom segment lights.
    public func pickRange(_ range: CustomRange) {
        calendarDate = range.start(calendar: calendar)
        calendarState.customMonths = range.months
        calendarState.range = .custom
    }
}
#endif
