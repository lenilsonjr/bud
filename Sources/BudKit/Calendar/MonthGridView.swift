#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The month: the weekday names over six rows of seven cells, each with its number, room for
/// the bars crossing it and its items. Bars are drawn over their row, one piece per week, in
/// their thread's colour, and clipped to the row; lanes the row has no room for become a
/// "+2 more" line in each cell they cross. The end of a bar that holds a day drags that day, the
/// scheduled one or the due one; an item drags its one day. While one is in hand the bud fades
/// where it is and is drawn again where it would land, the day under the pointer lights and is
/// said beside it; letting go on a day moves the bud there, by whole days. The grid in hand
/// keeps drawing as it is, so the piece or item the drag began on stays to finish it.
struct MonthGridView: View {
    let grid: MonthGrid
    /// A day let go on a day: the key, the bud and the day.
    let onMove: (DateKey, UUID, Date) -> Void
    @Environment(\.stillCalendarDrag) private var stillDrag
    /// The end or item in hand and where the pointer is, in the rows' space.
    @State private var inHand: CalendarDrag? = nil
    @GestureState private var holding = false

    /// The board's measures: the number's circle, the lane a bar takes, the bar itself.
    static let numberSize: CGFloat = 22
    static let laneHeight: CGFloat = 20
    static let barHeight: CGFloat = 18
    static let cellPadding: CGFloat = 6
    static let barInset: CGFloat = 4
    /// Where the first lane starts under a row's top: the padding, the number and a hair.
    static let laneTop: CGFloat = cellPadding + numberSize + 3
    /// What a row keeps under its lanes for an item or the "+2 more" line.
    static let itemRoom: CGFloat = 20
    /// How much of a bar's end takes the drag.
    static let handleWidth: CGFloat = 16
    /// The space the rows are measured in: the pointer and the cells agree on it.
    static let space = "calendar-month-rows"
    /// How faded the bud in hand is where it was.
    static let liftedOpacity = 0.35

    /// How many lanes a row of this height holds above the room for one line.
    static func lanes(fitting height: CGFloat) -> Int {
        max(0, Int((height - laneTop - itemRoom - cellPadding) / laneHeight))
    }

    var body: some View {
        let moving = inHand ?? stillDrag
        // The month as the drag would leave it, built from the placed entries; nil with nothing
        // in hand. Only the bud in hand is drawn from it, over the grid as it is.
        let preview = moving.map(grid.moving)
        VStack(spacing: 0) {
            weekdays
            GeometryReader { geo in
                let width = geo.size.width / CGFloat(CalendarMonth.columns)
                let height = geo.size.height / CGFloat(CalendarMonth.rows)
                let fits = Self.lanes(fitting: height)
                VStack(spacing: 0) {
                    ForEach(0..<CalendarMonth.rows, id: \.self) { row in
                        ZStack(alignment: .topLeading) {
                            HStack(spacing: 0) {
                                ForEach(0..<CalendarMonth.columns, id: \.self) { column in
                                    cell(row: row, column: column, fits: fits, moving: moving, preview: preview, size: geo.size)
                                        .frame(width: width, height: height)
                                }
                            }
                            ForEach(grid.bars(inRow: row, fitting: fits)) { bar in
                                piece(bar, width: width, size: geo.size)
                                    .opacity(moving?.entry == bar.entry ? Self.liftedOpacity : 1)
                            }
                            if let preview, let moving {
                                ForEach(preview.bars(inRow: row, fitting: fits).filter { $0.entry == moving.entry }) { bar in
                                    BarPiece(bar: bar, lifted: true)
                                        .frame(width: Self.width(of: bar, column: width), height: Self.barHeight)
                                        .offset(x: Self.x(of: bar, column: width), y: Self.y(of: bar))
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                        .frame(width: geo.size.width, height: height)
                        .clipped()
                    }
                }
                .coordinateSpace(name: Self.space)
                .overlay(alignment: .topLeading) {
                    if let moving, let over = moving.over {
                        dayChip(moving.key, over).offset(x: moving.point.x + 14, y: moving.point.y + 14)
                    }
                }
                .onChange(of: holding) { _, now in if !now { inHand = nil } }
            }
        }
        .background(Theme.surface)
        .accessibilityIdentifier("calendar-month")
    }

    private var weekdays: some View {
        HStack(spacing: 0) {
            ForEach(grid.month.weekdays, id: \.self) { name in
                Text(name)
                    .textStyle(TextStyle(typeface: .text, size: 10, weight: 700, tracking: 1.2))
                    .foregroundStyle(Theme.text3)
                    .padding(.leading, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 30)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
    }

    private func cell(row: Int, column: Int, fits: Int, moving: CalendarDrag?, preview: MonthGrid?, size: CGSize) -> some View {
        let day = grid.month.weeks[row][column]
        let quiet = !day.inMonth || day.isWeekend
        let target = moving?.over.map { grid.month.calendar.startOfDay(for: $0) } == day.date
        let room = min(grid.lanes[row], fits)
        let more = grid.overflow(row: row, column: column, fitting: fits)
        let items = grid.items(row: row, column: column)
        // The bud in hand as an item here, when this cell is a new place for it.
        let landing = (preview?.items(row: row, column: column) ?? []).filter { item in
            item.entry == moving?.entry && !items.contains { $0.entry == item.entry }
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(day.number)")
                .textStyle(TextStyle(typeface: .text, size: 12, weight: 600))
                .foregroundStyle(day.isToday ? Theme.onLeaf : day.inMonth ? Theme.text : Theme.text3)
                .frame(width: Self.numberSize, height: Self.numberSize)
                .background(day.isToday ? Theme.leaf : .clear, in: Circle())
                .accessibilityLabel(day.isToday ? "Today, \(day.number)" : "\(day.number)")
            // The lanes the row's bars take, so the items sit under them.
            if room > 0 {
                Color.clear.frame(width: 1, height: CGFloat(room) * Self.laneHeight)
            }
            if more > 0 {
                Text("+\(more) more")
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
                    .padding(.horizontal, 2)
            }
            ForEach(items) { item in
                itemRow(item, lifted: false)
                    .opacity(moving?.entry == item.entry ? Self.liftedOpacity : 1)
                    .gesture(lift(item.entry, item.isDue ? DateKey.due : DateKey.when, size: size))
            }
            ForEach(landing) { item in
                itemRow(item, lifted: true)
                    .allowsHitTesting(false)
            }
            Spacer(minLength: 0)
        }
        .padding(Self.cellPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(target ? Theme.leafFill : quiet ? Theme.sidebar : .clear)
        .overlay(alignment: .trailing) { Theme.line.frame(width: 1) }
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
        .overlay { if target { Rectangle().strokeBorder(Theme.leafLine, lineWidth: 1) } }
        .clipped()
    }

    /// One item in a cell: its thread's dot and its title. Lifted, it is the bud in hand where
    /// it would land, on the leaf fill.
    private func itemRow(_ item: MonthGrid.Item, lifted: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(item.tone.tone))
                .frame(width: 6, height: 6)
            Text(item.title)
                .textRole(.caption)
                .foregroundStyle(item.isDone ? Theme.text3 : Theme.text)
                .strikethrough(item.isDone, color: Theme.text3)
                .lineLimit(1)
        }
        .padding(.horizontal, 2)
        .background(lifted ? Theme.leafFill : .clear, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.isDue ? "due" : "scheduled")")
    }

    /// One piece of a bar in its lane, with a handle at each end that holds a day: the handle
    /// drags that day, whichever of the two it is.
    private func piece(_ bar: MonthGrid.Bar, width: CGFloat, size: CGSize) -> some View {
        BarPiece(bar: bar, lifted: false)
            .overlay(alignment: .leading) { handle(bar, at: .leading, size: size) }
            .overlay(alignment: .trailing) { handle(bar, at: .trailing, size: size) }
            .frame(width: Self.width(of: bar, column: width), height: Self.barHeight)
            .offset(x: Self.x(of: bar, column: width), y: Self.y(of: bar))
    }

    /// Where a piece sits in its row: across its columns, inset at each end, in its lane.
    static func width(of bar: MonthGrid.Bar, column: CGFloat) -> CGFloat { CGFloat(bar.columns) * column - 2 * barInset }
    static func x(of bar: MonthGrid.Bar, column: CGFloat) -> CGFloat { CGFloat(bar.from) * column + barInset }
    static func y(of bar: MonthGrid.Bar) -> CGFloat { laneTop + CGFloat(bar.lane) * laneHeight }

    /// The strip at a bar's end that takes the drag: clear, over the piece, the width of a
    /// thumb. Nothing at an end that is only the week's edge.
    @ViewBuilder private func handle(_ bar: MonthGrid.Bar, at end: MonthGrid.Bar.End, size: CGSize) -> some View {
        if let key = bar.key(at: end) {
            Color.clear
                .frame(width: Self.handleWidth)
                .contentShape(Rectangle())
                .gesture(lift(bar.entry, key, size: size))
                .accessibilityHidden(true)
        }
    }

    /// The drag that lifts a day: the pointer and the day under it while it moves, the move when
    /// it lets go on a day, nothing when it lets go off the grid.
    private func lift(_ entry: UUID, _ key: DateKey, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .updating($holding) { _, state, _ in state = true }
            .onChanged { value in
                inHand = CalendarDrag(entry: entry, key: key, point: value.location, over: grid.month.day(under: value.location, in: size))
            }
            .onEnded { value in
                if let day = grid.month.day(under: value.location, in: size) { onMove(key, entry, day) }
                inHand = nil
            }
    }

    /// The day under the pointer, said beside it: the arrow or the flag and "14 Nov".
    private func dayChip(_ key: DateKey, _ day: Date) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
        return HStack(spacing: 5) {
            Image(systemName: key.symbol)
                .textRole(.caption)
                .foregroundStyle(Theme.leaf)
            Text(DayText.short(day, calendar: grid.month.calendar))
                .textStyle(TextStyle(typeface: .text, size: 11, weight: 600))
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Theme.raised, in: shape)
        .overlay(shape.stroke(Theme.leafLine, lineWidth: 1))
        .shadow(color: Theme.shadow, radius: 6, y: 3)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One week's piece of a bar: the thread's soft fill and line, an arrow where the bud is
/// scheduled, a flag and "due 4 Dec" where it is due, the title between. A piece holding both
/// days leads with the arrow and ends with the flag. Lifted, it draws the leaf line instead of
/// its thread's, since it is where the bud would land, not where it is.
struct BarPiece: View {
    let bar: MonthGrid.Bar
    let lifted: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
        let tone = Color(bar.tone.tone)
        HStack(spacing: 5) {
            if let symbol = leading {
                Image(systemName: symbol)
                    .textRole(.caption)
                    .foregroundStyle(tone)
                    .accessibilityHidden(true)
            }
            Text(label)
                .textStyle(TextStyle(typeface: .text, size: 11, weight: 600))
                .foregroundStyle(bar.isDone ? Theme.text3 : Theme.text)
                .strikethrough(bar.isDone, color: Theme.text3)
                .lineLimit(1)
            Spacer(minLength: 0)
            if bar.starts && bar.dueLabel != nil {
                Image(systemName: "flag")
                    .textRole(.caption)
                    .foregroundStyle(tone)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 7)
        .frame(maxHeight: .infinity)
        .background(Color(bar.tone.soft), in: shape)
        .overlay(shape.stroke(lifted ? Theme.leaf : tone, lineWidth: lifted ? 1.5 : 1))
        .clipShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    /// The arrow where the bud is scheduled; else the flag where it is due; else nothing.
    private var leading: String? {
        if bar.starts { return "arrow.right" }
        return bar.dueLabel != nil ? "flag" : nil
    }

    private var label: String {
        bar.dueLabel.map { "\(bar.title) · \($0)" } ?? bar.title
    }
}

/// The end or item a still picture shows in hand, since a picture has no pointer to drag one.
struct StillCalendarDragKey: EnvironmentKey {
    static let defaultValue: CalendarDrag? = nil
}

extension EnvironmentValues {
    var stillCalendarDrag: CalendarDrag? {
        get { self[StillCalendarDragKey.self] }
        set { self[StillCalendarDragKey.self] = newValue }
    }
}
#endif
