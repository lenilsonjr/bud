import Foundation

/// The colour a thread draws in: one of the palette's four accents, by the thread's place under
/// the centre. The tokens stay in `Palette`; this only names which pair a thread gets.
public enum ThreadTone: String, CaseIterable, Codable, Sendable {
    case leaf, amethyst, pistil, rose

    /// The accent and its soft fill, as the palette has them.
    public var tone: Tone {
        switch self {
        case .leaf: return Palette.leaf
        case .amethyst: return Palette.amethyst
        case .pistil: return Palette.pistil
        case .rose: return Palette.rose
        }
    }

    public var soft: Tone {
        switch self {
        case .leaf: return Palette.leafSoft
        case .amethyst: return Palette.amethystSoft
        case .pistil: return Palette.pistilSoft
        case .rose: return Palette.roseSoft
        }
    }

    /// The tone of the thread at `index` under the centre: the four accents in turn, then again.
    public static func at(_ index: Int) -> ThreadTone {
        allCases[((index % allCases.count) + allCases.count) % allCases.count]
    }
}

/// A thread: a top-level branch of the centre bud, with the colour its buds draw in.
public struct CalendarThread: Hashable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let tone: ThreadTone

    /// Every thread under Everything in its order, coloured in turn.
    public static func list(in tree: Tree) -> [CalendarThread] {
        tree.children(of: rootID).enumerated().map { index, bud in
            CalendarThread(id: bud.id, title: bud.text, tone: .at(index))
        }
    }
}

/// A bud the calendar can draw: its thread, its dates as days, and what the switches read.
public struct CalendarEntry: Hashable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    /// The top-level branch it sits under; the bud itself when it is one.
    public let thread: UUID
    public let tone: ThreadTone
    /// Midnight of the scheduled day and of the due day, in the calendar's zone.
    public let when: Date?
    public let due: Date?
    /// The moments as the bud carries them, with their time of day: what the Day and Week
    /// views place by the hour.
    public let whenAt: Date?
    public let dueAt: Date?
    public let isDone: Bool
    /// Stamped by a trigger: its `from` key starts with `tpl/`.
    public let isRoutine: Bool

    /// Every bud under Everything with a day to show, in reading order, from one walk of the
    /// tree: a bud reads after its thread, so the thread in hand is the one it sits under. A
    /// routine without a date shows on the day its trigger stamped it for, read from its key.
    public static func all(in tree: Tree, calendar: Calendar = .current) -> [CalendarEntry] {
        var out: [CalendarEntry] = []
        var thread: CalendarThread?
        var index = -1
        for bud in tree.walk(under: rootID) {
            if bud.parent == rootID {
                index += 1
                thread = CalendarThread(id: bud.id, title: bud.text, tone: .at(index))
            }
            guard let thread else { continue }
            let routine = bud.from?.hasPrefix("tpl/") ?? false
            var whenAt = bud.when
            if routine, whenAt == nil, bud.due == nil, let stamped = bud.from.flatMap(Tree.stampOccurrence) {
                whenAt = stamped
            }
            let when = whenAt.map { calendar.startOfDay(for: $0) }
            let due = bud.due.map { calendar.startOfDay(for: $0) }
            guard when != nil || due != nil else { continue }
            out.append(CalendarEntry(
                id: bud.id, title: bud.text, thread: thread.id, tone: thread.tone,
                when: when, due: due, whenAt: whenAt, dueAt: bud.due, isDone: bud.isDone, isRoutine: routine
            ))
        }
        return out
    }
}

/// The month grid with its buds placed: a bud with two days is a bar from one to the other,
/// cut at each week's end and continued on the next row; a bud with one day is an item in
/// that day's cell. Bars stack in lanes so none covers another; items sit below the lanes.
public struct MonthGrid: Equatable, Sendable {
    /// One week's piece of a bar.
    public struct Bar: Hashable, Identifiable, Sendable {
        public let entry: UUID
        public let title: String
        public let tone: ThreadTone
        public let row: Int
        /// The first and last column it covers, inclusive.
        public let from: Int
        public let to: Int
        /// Which lane of the row it takes, 0 at the top.
        public let lane: Int
        /// True where the bud's scheduled day is: the piece draws an arrow.
        public let starts: Bool
        /// The due day, when it falls in this piece: the piece draws a flag and says "due 4 Dec".
        public let dueLabel: String?
        public let isDone: Bool

        public var id: String { "\(entry)-\(row)" }
        public var columns: Int { to - from + 1 }
        public func covers(_ column: Int) -> Bool { column >= from && column <= to }
    }

    /// A bud on one day.
    public struct Item: Hashable, Identifiable, Sendable {
        public let entry: UUID
        public let title: String
        public let tone: ThreadTone
        public let row: Int
        public let column: Int
        public let isDone: Bool
        /// True when the day shown is the due day, false for the scheduled one.
        public let isDue: Bool

        public var id: String { "\(entry)-\(isDue ? "due" : "when")" }
    }

    public let month: CalendarMonth
    public let bars: [Bar]
    public let items: [Item]
    /// How many lanes each row's bars take, so the cells leave room above their items.
    public let lanes: [Int]

    /// Places the entries the state shows on the month.
    public init(month: CalendarMonth, entries: [CalendarEntry], state: CalendarState) {
        self.month = month
        let calendar = month.calendar
        var bars: [Bar] = []
        var items: [Item] = []
        // The columns each lane of each row has taken, so a new piece finds the first free lane.
        var taken: [[[ClosedRange<Int>]]] = Array(repeating: [], count: CalendarMonth.rows)
        var lanes = Array(repeating: 0, count: CalendarMonth.rows)

        // Longer bars first, then by start, so the long ones keep the top lanes across rows. A
        // span runs from the earlier of the two days to the later, whichever is which.
        let shown = entries.filter(state.shows)
        let spans: [(entry: CalendarEntry, start: Date, end: Date)] = shown.compactMap { entry in
            let dates = state.dates(of: entry)
            guard let start = dates.min(), let end = dates.max(), start < end else { return nil }
            return (entry, start, end)
        }.sorted { a, b in
            if a.end.timeIntervalSince(a.start) != b.end.timeIntervalSince(b.start) { return a.end.timeIntervalSince(a.start) > b.end.timeIntervalSince(b.start) }
            return (a.start, a.entry.title) < (b.start, b.entry.title)
        }
        for span in spans {
            let first = max(span.start, month.gridStart)
            let last = min(span.end, calendar.date(byAdding: .day, value: -1, to: month.gridEnd) ?? month.gridStart)
            guard first <= last, let head = month.cell(of: first), let tail = month.cell(of: last) else { continue }
            for row in head.row...tail.row {
                let from = row == head.row ? head.column : 0
                let to = row == tail.row ? tail.column : CalendarMonth.columns - 1
                var lane = 0
                while taken[row].indices.contains(lane) && taken[row][lane].contains(where: { $0.overlaps(from...to) }) { lane += 1 }
                if lane == taken[row].count { taken[row].append([]) }
                taken[row][lane].append(from...to)
                lanes[row] = max(lanes[row], lane + 1)
                let piece = month.weeks[row][from].date...month.weeks[row][to].date
                let whenHere = span.entry.when.map(piece.contains) ?? false
                let dueHere = span.entry.due.map(piece.contains) ?? false
                bars.append(Bar(
                    entry: span.entry.id, title: span.entry.title, tone: span.entry.tone, row: row, from: from, to: to, lane: lane,
                    starts: whenHere,
                    dueLabel: dueHere ? "due \(DayText.short(span.entry.due!, calendar: calendar))" : nil,
                    isDone: span.entry.isDone
                ))
            }
        }
        let spanned = Set(spans.map(\.entry.id))
        for entry in shown where !spanned.contains(entry.id) {
            // One day, or both dates on the same day: the due day wins the flag.
            let dates = state.dates(of: entry)
            guard let day = dates.first, let cell = month.cell(of: day) else { continue }
            let isDue = state.shows(.due) && entry.due == day
            items.append(Item(entry: entry.id, title: entry.title, tone: entry.tone, row: cell.row, column: cell.column, isDone: entry.isDone, isDue: isDue))
        }
        self.bars = bars
        self.items = items.sorted { ($0.row, $0.column, $0.title) < ($1.row, $1.column, $1.title) }
        self.lanes = lanes
    }

    /// The items in one cell, in title order.
    public func items(row: Int, column: Int) -> [Item] {
        items.filter { $0.row == row && $0.column == column }
    }

    public func bars(inRow row: Int) -> [Bar] {
        bars.filter { $0.row == row }
    }

    /// The bars of a row the cells have room for: the first `fits` lanes.
    public func bars(inRow row: Int, fitting fits: Int) -> [Bar] {
        bars.filter { $0.row == row && $0.lane < fits }
    }

    /// How many bars cross a cell below the lanes it has room for: the "+2 more" in that cell.
    public func overflow(row: Int, column: Int, fitting fits: Int) -> Int {
        bars.filter { $0.row == row && $0.lane >= fits && $0.covers(column) }.count
    }
}
