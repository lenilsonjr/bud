import Foundation

/// One month of one year, as the range picker counts them: November 2026 is `(2026, 11)`. Pure,
/// so a range travels through the saved state and compares without a calendar.
public struct YearMonth: Hashable, Comparable, Codable, Sendable {
    public let year: Int
    /// 1 to 12.
    public let month: Int

    public init(year: Int, month: Int) {
        // A month outside 1...12 rolls into the next or previous year.
        let index = year * 12 + (month - 1)
        self.year = Int((Double(index) / 12).rounded(.down))
        self.month = ((index % 12) + 12) % 12 + 1
    }

    /// The month holding `date`.
    public init(containing date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1)
    }

    public static func < (a: YearMonth, b: YearMonth) -> Bool { (a.year, a.month) < (b.year, b.month) }

    /// `steps` months later, or earlier when negative.
    public func adding(_ steps: Int) -> YearMonth { YearMonth(year: year, month: month + steps) }

    /// How many months from `other` to this one: December from November is 1.
    public func months(since other: YearMonth) -> Int { (year - other.year) * 12 + (month - other.month) }

    /// Midnight of the month's first day in the calendar's zone.
    public func start(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date(timeIntervalSince1970: 0)
    }

    /// "Nov", "Nov 2026" or "November 2026", the formats written out so they read the same on
    /// every platform.
    public func text(_ format: String, calendar: Calendar = .current) -> String {
        DayText.formatter(format: format, calendar: calendar).string(from: start(calendar: calendar))
    }
}

/// The custom range: a first and a last month, inclusive. Its title over the grid, its length
/// under it, and the step the chevrons move it by, which is its own length.
public struct CustomRange: Hashable, Codable, Sendable {
    public let first: YearMonth
    public let last: YearMonth

    /// The two months in either order.
    public init(first: YearMonth, last: YearMonth) {
        self.first = min(first, last)
        self.last = max(first, last)
    }

    /// `count` months from `first`.
    public init(from first: YearMonth, months count: Int) {
        self.init(first: first, last: first.adding(max(count, 1) - 1))
    }

    /// How many months it spans, at least one.
    public var months: Int { last.months(since: first) + 1 }

    /// Every month in it, first to last.
    public var all: [YearMonth] { (0..<months).map(first.adding) }

    public func contains(_ month: YearMonth) -> Bool { month >= first && month <= last }

    /// Midnight of the first day, and midnight of the day after the last: what a bar is clipped to.
    public func start(calendar: Calendar = .current) -> Date { first.start(calendar: calendar) }
    public func end(calendar: Calendar = .current) -> Date { last.adding(1).start(calendar: calendar) }

    /// The range its own length later, or earlier when negative.
    public func shifted(by steps: Int) -> CustomRange {
        CustomRange(first: first.adding(steps * months), last: last.adding(steps * months))
    }

    /// "Nov 2026 – Feb 2027"; "Nov – Dec 2026" within a year; "November 2026" for one month.
    public func title(calendar: Calendar = .current) -> String {
        if months == 1 { return first.text("MMMM yyyy", calendar: calendar) }
        if first.year == last.year {
            return "\(first.text("MMM", calendar: calendar)) – \(last.text("MMM yyyy", calendar: calendar))"
        }
        return "\(first.text("MMM yyyy", calendar: calendar)) – \(last.text("MMM yyyy", calendar: calendar))"
    }

    /// "4 months", "1 month": the line beside the title.
    public var lengthLine: String { months == 1 ? "1 month" : "\(months) months" }

    // MARK: The presets

    /// This month and the two after it.
    public static func nextThreeMonths(from now: Date, calendar: Calendar = .current) -> CustomRange {
        CustomRange(from: YearMonth(containing: now, calendar: calendar), months: 3)
    }

    /// The half of the year today falls in: January to June, or July to December.
    public static func thisHalf(from now: Date, calendar: Calendar = .current) -> CustomRange {
        let month = YearMonth(containing: now, calendar: calendar)
        let first = YearMonth(year: month.year, month: month.month <= 6 ? 1 : 7)
        return CustomRange(from: first, months: 6)
    }

    /// From this month to the month a thread is due in; this month alone when the due day has
    /// passed.
    public static func until(_ due: Date, from now: Date, calendar: Calendar = .current) -> CustomRange {
        let month = YearMonth(containing: now, calendar: calendar)
        return CustomRange(first: month, last: max(month, YearMonth(containing: due, calendar: calendar)))
    }
}

/// One row of the picker's presets: its line, its symbol and the range it picks. A thread's
/// row is told apart by the thread's id, so two threads named alike are two rows.
public struct RangePreset: Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    /// The SF Symbol before the line.
    public let symbol: String
    public let range: CustomRange

    /// The presets for today and the threads: Next 3 months, This half, then one "Until … is
    /// due" for each thread due this month or later, nearest first.
    public static func all(now: Date, threads: [(id: UUID, title: String, due: Date?)], calendar: Calendar = .current) -> [RangePreset] {
        var out = [
            RangePreset(id: "next-three-months", title: "Next 3 months", symbol: "calendar", range: .nextThreeMonths(from: now, calendar: calendar)),
            RangePreset(id: "this-half", title: "This half", symbol: "calendar", range: .thisHalf(from: now, calendar: calendar)),
        ]
        let month = YearMonth(containing: now, calendar: calendar)
        let due = threads
            .compactMap { thread in thread.due.map { (id: thread.id, title: thread.title, due: $0) } }
            .filter { YearMonth(containing: $0.due, calendar: calendar) >= month }
            .sorted { ($0.due, $0.title) < ($1.due, $1.title) }
        for thread in due {
            out.append(RangePreset(id: "until-\(thread.id.uuidString)", title: "Until \(thread.title) is due", symbol: "flag", range: .until(thread.due, from: now, calendar: calendar)))
        }
        return out
    }
}

/// What the picker holds while a range is being picked: the first month tapped, then the last.
/// A third tap starts over. Pure, so the taps are tested without a view.
public struct RangePick: Equatable, Sendable {
    public var first: YearMonth?
    public var last: YearMonth?

    /// Empty, or holding the range on show so its months are lit when the picker opens.
    public init(_ range: CustomRange? = nil) {
        first = range?.first
        last = range?.last
    }

    /// The range picked so far: both months, or nil until the last is tapped.
    public var range: CustomRange? {
        guard let first, let last else { return nil }
        return CustomRange(first: first, last: last)
    }

    /// Whether `month` is the first, the last, or between them: what the chip draws.
    public func isEnd(_ month: YearMonth) -> Bool { month == first || month == last }
    public func isBetween(_ month: YearMonth) -> Bool {
        guard let first, let last else { return false }
        return month > first && month < last
    }

    /// A tap on a month: the first when none is picked; the last when the first is, in either
    /// order; and a fresh first once both are.
    public mutating func tap(_ month: YearMonth) {
        if first == nil || last != nil {
            first = month
            last = nil
        } else {
            last = month
            if let start = first, start > month {
                first = month
                last = start
            }
        }
    }

    /// The years the picker lays out: this year and the next, stretched to hold the range.
    public static func years(now: Date, holding range: CustomRange?, calendar: Calendar = .current) -> [Int] {
        let year = calendar.component(.year, from: now)
        let from = min(year, range?.first.year ?? year)
        let to = max(year + 1, range?.last.year ?? year + 1)
        return Array(from...to)
    }

    /// "Show 4 months", "Show 1 month"; "Show" while nothing is picked.
    public var showLine: String { range.map { "Show \($0.lengthLine)" } ?? "Show" }
}
