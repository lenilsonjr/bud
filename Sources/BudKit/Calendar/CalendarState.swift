import Foundation

/// How much time the calendar shows at once: the segments in its bar, in their order. The month
/// is built; the others are drawn and selectable and say they are coming.
public enum CalendarRange: String, CaseIterable, Codable, Sendable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case quarter = "Quarter"
    case year = "Year"
    case custom = "Custom"

    /// The one line in the grid's place while the range is not built: "The week view is coming."
    public var comingLine: String {
        self == .custom ? "The custom range is coming." : "The \(rawValue.lowercased()) view is coming."
    }

    /// The title over the grid for the date it shows: "November 2026", "Q4 2026", "2026".
    public func title(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        switch self {
        case .day:
            formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM yyyy")
            return formatter.string(from: date)
        case .week:
            let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            formatter.setLocalizedDateFormatFromTemplate("d MMM")
            let year = calendar.component(.year, from: end)
            return "\(formatter.string(from: start)) – \(formatter.string(from: end)) \(year)"
        case .month, .custom:
            formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
            return formatter.string(from: date)
        case .quarter:
            let quarter = (calendar.component(.month, from: date) - 1) / 3 + 1
            return "Q\(quarter) \(calendar.component(.year, from: date))"
        case .year:
            return String(calendar.component(.year, from: date))
        }
    }
}

/// The two ways of drawing a range: a grid of days, or threads along time.
public enum CalendarLayout: String, CaseIterable, Codable, Sendable {
    case calendar = "Calendar"
    case timeline = "Timeline"

    public var comingLine: String { "The timeline is coming." }
}

/// The Show switches in the left column, in their order: which dates and which buds the grid draws.
public enum CalendarShow: String, CaseIterable, Codable, Sendable {
    /// Buds on the day they are scheduled for.
    case when = "When"
    /// Buds on the day they are due.
    case due = "Due"
    /// Buds a trigger stamped.
    case routines = "Routines"
    /// Buds that are done.
    case done = "Done"
}

/// What this device chose for the calendar: the range, the layout, the threads hidden and the Show
/// switches. It is this device's alone, so the toggles do not travel with the vault.
public struct CalendarState: Equatable, Codable, Sendable {
    public var range: CalendarRange = .month
    public var layout: CalendarLayout = .calendar
    /// Threads whose row is unticked; every thread shows until it is hidden.
    public var hiddenThreads: Set<UUID> = []
    /// The switches that are on. Done starts off, as the board draws it.
    public var shown: Set<CalendarShow> = [.when, .due, .routines]

    public init(range: CalendarRange = .month, layout: CalendarLayout = .calendar, hiddenThreads: Set<UUID> = [], shown: Set<CalendarShow> = [.when, .due, .routines]) {
        self.range = range
        self.layout = layout
        self.hiddenThreads = hiddenThreads
        self.shown = shown
    }

    /// A state saved before a field existed still loads: each has its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        range = try c.decodeIfPresent(CalendarRange.self, forKey: .range) ?? .month
        layout = try c.decodeIfPresent(CalendarLayout.self, forKey: .layout) ?? .calendar
        hiddenThreads = try c.decodeIfPresent(Set<UUID>.self, forKey: .hiddenThreads) ?? []
        shown = try c.decodeIfPresent(Set<CalendarShow>.self, forKey: .shown) ?? [.when, .due, .routines]
    }

    public func shows(_ show: CalendarShow) -> Bool { shown.contains(show) }
    public func shows(thread id: UUID) -> Bool { !hiddenThreads.contains(id) }

    public mutating func toggle(_ show: CalendarShow) {
        if shown.contains(show) { shown.remove(show) } else { shown.insert(show) }
    }

    public mutating func toggle(thread id: UUID) {
        if hiddenThreads.contains(id) { hiddenThreads.remove(id) } else { hiddenThreads.insert(id) }
    }

    /// Whether a bud passes the switches: a routine needs Routines on, a done bud needs Done on,
    /// and at least one of its dates must be shown by its switch.
    public func shows(_ entry: CalendarEntry) -> Bool {
        guard shows(thread: entry.thread) else { return false }
        if entry.isRoutine && !shows(.routines) { return false }
        if entry.isDone && !shows(.done) { return false }
        return !dates(of: entry).isEmpty
    }

    /// The dates the switches leave on a bud, When then Due; empty when both are off or absent.
    public func dates(of entry: CalendarEntry) -> [Date] {
        var out: [Date] = []
        if let when = entry.when, shows(.when) { out.append(when) }
        if let due = entry.due, shows(.due) { out.append(due) }
        return out
    }

    // MARK: Kept on this device

    static let key = "calendar"

    /// The state saved on this device, or the defaults.
    public static func load(from defaults: UserDefaults) -> CalendarState {
        guard let data = defaults.data(forKey: key), let state = try? JSONDecoder().decode(CalendarState.self, from: data) else {
            return CalendarState()
        }
        return state
    }

    public func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
