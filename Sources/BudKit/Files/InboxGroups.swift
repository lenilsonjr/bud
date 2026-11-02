import Foundation

/// The Inbox shows All, only the raw captures (nothing inside yet) or only the enriched ones.
public enum InboxFilter: String, CaseIterable, Sendable {
    case all = "All"
    case raw = "Raw"
    case enriched = "Enriched"
}

/// One day of captures: the day, the word for it (Today, Yesterday, or a date like Thu 30 Oct)
/// and the captures, newest first.
public struct InboxGroup: Equatable, Sendable {
    public let day: Date
    public let label: String
    public let buds: [Bud]
}

extension Tree {
    /// A capture is raw until something is planted inside it.
    public func isRaw(_ id: UUID) -> Bool {
        !hasChildren(id)
    }

    /// The Inbox by day, newest day first, newest capture first within a day.
    public func inboxGroups(_ filter: InboxFilter = .all, now: Date = Date(), calendar: Calendar = .current) -> [InboxGroup] {
        let kept = inbox().filter { bud in
            switch filter {
            case .all: return true
            case .raw: return isRaw(bud.id)
            case .enriched: return !isRaw(bud.id)
            }
        }
        let byDay = Dictionary(grouping: kept) { calendar.startOfDay(for: $0.created) }
        return byDay.keys.sorted(by: >).map { day in
            InboxGroup(
                day: day,
                label: Self.dayLabel(for: day, now: now, calendar: calendar),
                buds: byDay[day]!.sorted { $0.created > $1.created }
            )
        }
    }

    /// Today, Yesterday, or the day as Thu 30 Oct, with the names in the calendar's locale.
    public static func dayLabel(for day: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: day)
    }
}
