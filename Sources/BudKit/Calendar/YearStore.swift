import Foundation

// MARK: the year and the custom range

#if canImport(SwiftUI)
extension BudStore {
    /// The custom range on show: the one picked, or the next three months until one is.
    public var customRange: CustomRange {
        calendarState.custom ?? .nextThreeMonths(from: now, calendar: calendar)
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
        RangePreset.all(now: now, threads: tree.children(of: rootID).map { ($0.text, $0.due) }, calendar: calendar)
    }

    /// Shows a custom range: the Custom segment lights and the grid draws its months.
    public func pickRange(_ range: CustomRange) {
        calendarState.custom = range
        calendarState.range = .custom
    }

    /// Moves the custom range its own length back or forward.
    public func shiftCustomRange(by steps: Int) {
        calendarState.custom = customRange.shifted(by: steps)
    }
}
#endif
