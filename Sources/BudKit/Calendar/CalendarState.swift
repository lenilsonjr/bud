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

    /// What one step of the chevrons moves: "month" in "Previous month". A custom range steps by
    /// its own length.
    public var stepName: String {
        self == .custom ? "range" : rawValue.lowercased()
    }

    /// The date `steps` of this range away: a day, a week, a month, three months or a year each;
    /// the custom range's own months, three until one is picked.
    public func shift(_ date: Date, by steps: Int, custom: CustomRange? = nil, calendar: Calendar = .current) -> Date {
        let (component, count): (Calendar.Component, Int) = {
            switch self {
            case .day: return (.day, steps)
            case .week: return (.weekOfYear, steps)
            case .month: return (.month, steps)
            case .quarter: return (.month, 3 * steps)
            case .year: return (.year, steps)
            case .custom: return (.month, steps * (custom?.months ?? CalendarState.defaultCustomMonths))
            }
        }()
        return calendar.date(byAdding: component, value: count, to: date) ?? date
    }

    /// The title over the grid for the date it shows: "Tuesday, 3 November 2026", "2 Nov – 8 Nov
    /// 2026", "November 2026", "Q4 2026", "2026", "Nov 2026 – Jan 2027". The formats are written
    /// out, so the title reads the same on every platform and matches the board.
    public func title(for date: Date, custom: CustomRange? = nil, calendar: Calendar = .current) -> String {
        switch self {
        case .day:
            let weekday = DayText.formatter(format: "EEEE", calendar: calendar).string(from: date)
            return "\(weekday), \(DayText.formatter(format: "d MMMM yyyy", calendar: calendar).string(from: date))"
        case .week:
            let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            let short = DayText.formatter(format: "d MMM", calendar: calendar)
            return "\(short.string(from: start)) – \(short.string(from: end)) \(calendar.component(.year, from: end))"
        case .month:
            return DayText.formatter(format: "MMMM yyyy", calendar: calendar).string(from: date)
        case .custom:
            let range = custom ?? CustomRange(from: YearMonth(containing: date, calendar: calendar), months: CalendarState.defaultCustomMonths)
            return range.title(calendar: calendar)
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
    /// The switches on at first: everything but Done, as the board draws its toggles.
    public static let defaultShown: Set<CalendarShow> = [.when, .due, .routines]
    /// How many months Custom shows until a range is picked: the next three.
    public static let defaultCustomMonths = 3

    public var range: CalendarRange = .month
    public var layout: CalendarLayout = .calendar
    /// Threads whose row is unticked; every thread shows until it is hidden.
    public var hiddenThreads: Set<UUID> = []
    /// Threads folded to their header in the timeline; every thread opens until it is folded.
    public var collapsedThreads: Set<UUID> = []
    /// The switches that are on.
    public var shown: Set<CalendarShow> = CalendarState.defaultShown
    /// How many months the custom range spans. Where it starts is the day the calendar looks
    /// at, as for every range, so Today, the chevrons and the picker all move the one date.
    public var customMonths: Int = CalendarState.defaultCustomMonths

    public init(range: CalendarRange = .month, layout: CalendarLayout = .calendar, hiddenThreads: Set<UUID> = [], collapsedThreads: Set<UUID> = [], shown: Set<CalendarShow> = CalendarState.defaultShown, customMonths: Int = CalendarState.defaultCustomMonths) {
        self.range = range
        self.layout = layout
        self.hiddenThreads = hiddenThreads
        self.collapsedThreads = collapsedThreads
        self.shown = shown
        self.customMonths = max(customMonths, 1)
    }

    /// A state saved before a field existed still loads: each has its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        range = try c.decodeIfPresent(CalendarRange.self, forKey: .range) ?? .month
        layout = try c.decodeIfPresent(CalendarLayout.self, forKey: .layout) ?? .calendar
        hiddenThreads = try c.decodeIfPresent(Set<UUID>.self, forKey: .hiddenThreads) ?? []
        collapsedThreads = try c.decodeIfPresent(Set<UUID>.self, forKey: .collapsedThreads) ?? []
        shown = try c.decodeIfPresent(Set<CalendarShow>.self, forKey: .shown) ?? Self.defaultShown
        customMonths = max(try c.decodeIfPresent(Int.self, forKey: .customMonths) ?? Self.defaultCustomMonths, 1)
    }

    public func shows(_ show: CalendarShow) -> Bool { shown.contains(show) }
    public func shows(thread id: UUID) -> Bool { !hiddenThreads.contains(id) }

    public mutating func toggle(_ show: CalendarShow) {
        if shown.contains(show) { shown.remove(show) } else { shown.insert(show) }
    }

    public mutating func toggle(thread id: UUID) {
        if hiddenThreads.contains(id) { hiddenThreads.remove(id) } else { hiddenThreads.insert(id) }
    }

    public func isCollapsed(thread id: UUID) -> Bool { collapsedThreads.contains(id) }

    /// Folds a thread's rows up under its header, or opens them again.
    public mutating func toggle(collapsed id: UUID) {
        if collapsedThreads.contains(id) { collapsedThreads.remove(id) } else { collapsedThreads.insert(id) }
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
