import Foundation

/// One of a bud's two days, by its front matter key: what a drag on the calendar moves.
public enum DateKey: String, CaseIterable, Sendable {
    /// The day the bud is scheduled for: a bar's leading edge, the arrow.
    case when
    /// The day it is due: a bar's trailing edge, the flag.
    case due

    /// The date `date` moved onto `day`, keeping its time of day: whole days are added, so a
    /// morning stays a morning across the move.
    public func moved(_ date: Date, toDay day: Date, calendar: Calendar) -> Date {
        let from = calendar.startOfDay(for: date)
        let to = calendar.startOfDay(for: day)
        let days = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        return calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    /// The symbol the day draws with: the arrow for when, the flag for due.
    public var symbol: String { self == .when ? "arrow.right" : "flag" }
}

/// A bar's end or an item in hand: which bud, which of its days, where the pointer is in the
/// grid, and the day under it, nil off the grid. A still picture sets one to show the move.
public struct CalendarDrag: Equatable, Sendable {
    public var entry: UUID
    public var key: DateKey
    public var point: CGPoint
    public var over: Date?

    public init(entry: UUID, key: DateKey, point: CGPoint, over: Date? = nil) {
        self.entry = entry
        self.key = key
        self.point = point
        self.over = over
    }
}

extension CalendarEntry {
    /// The entry with one of its days moved onto `day`, at midnight as the grid holds its days;
    /// the other day as it was. What the grid draws while the end is in hand.
    public func moved(_ key: DateKey, toDay day: Date, calendar: Calendar) -> CalendarEntry {
        let midnight = calendar.startOfDay(for: day)
        return CalendarEntry(
            id: id, title: title, thread: thread, tone: tone,
            when: key == .when ? midnight : when, due: key == .due ? midnight : due,
            whenAt: key == .when ? midnight : whenAt, dueAt: key == .due ? midnight : dueAt,
            isDone: isDone, isRoutine: isRoutine
        )
    }
}

extension CalendarMonth {
    /// The day under a point in the grid of `size`: six rows of seven cells, each the same
    /// size. Nil outside the grid.
    public func day(under point: CGPoint, in size: CGSize) -> Date? {
        guard size.width > 0, size.height > 0, point.x >= 0, point.y >= 0, point.x < size.width, point.y < size.height else { return nil }
        let column = Int(point.x / (size.width / CGFloat(Self.columns)))
        let row = Int(point.y / (size.height / CGFloat(Self.rows)))
        guard weeks.indices.contains(row), weeks[row].indices.contains(column) else { return nil }
        return weeks[row][column].date
    }
}

extension Array where Element == CalendarEntry {
    /// The entries as they stand with the drag applied: the bud in hand has its day on the one
    /// under the pointer, or nothing moves while the pointer is off the grid.
    public func moving(_ drag: CalendarDrag?, calendar: Calendar) -> [CalendarEntry] {
        guard let drag, let over = drag.over else { return self }
        return map { $0.id == drag.entry ? $0.moved(drag.key, toDay: over, calendar: calendar) : $0 }
    }
}
