#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The month: the weekday names over six rows of seven cells, each with its number, room for
/// the bars crossing it and its items. Bars are drawn over their row, one piece per week, in
/// their thread's colour, and clipped to the row; lanes the row has no room for become a
/// "+2 more" line in each cell they cross. A bar's leading edge drags its scheduled day and its
/// trailing edge its due day; an item drags its one day. While one is in hand the grid draws the
/// bud where it would land, lights the day under the pointer and says the day beside it; letting
/// go on a day moves the bud there, by whole days.
struct MonthGridView: View {
    let grid: MonthGrid
    /// The month with a drag applied, from the store, so the bud in hand is drawn where it would land.
    let preview: (CalendarDrag) -> MonthGrid
    /// A day let go on a day: the field, the bud and the day.
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

    /// How many lanes a row of this height holds above the room for one line.
    static func lanes(fitting height: CGFloat) -> Int {
        max(0, Int((height - laneTop - itemRoom - cellPadding) / laneHeight))
    }

    var body: some View {
        let moving = inHand ?? stillDrag
        let shown = moving.map(preview) ?? grid
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
                                    cell(row: row, column: column, in: shown, fits: fits, moving: moving, size: geo.size)
                                        .frame(width: width, height: height)
                                }
                            }
                            ForEach(shown.bars(inRow: row, fitting: fits)) { bar in
                                piece(bar, lifted: moving?.entry == bar.entry, width: width, size: geo.size)
                            }
                        }
                        .frame(width: geo.size.width, height: height)
                        .clipped()
                    }
                }
                .coordinateSpace(name: Self.space)
                .overlay(alignment: .topLeading) {
                    if let moving, let over = moving.over {
                        dayChip(moving.field, over).offset(x: moving.point.x + 14, y: moving.point.y + 14)
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

    private func cell(row: Int, column: Int, in shown: MonthGrid, fits: Int, moving: CalendarDrag?, size: CGSize) -> some View {
        let day = shown.month.weeks[row][column]
        let quiet = !day.inMonth || day.isWeekend
        let target = moving?.over == day.date
        let room = min(shown.lanes[row], fits)
        let more = shown.overflow(row: row, column: column, fitting: fits)
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
            ForEach(shown.items(row: row, column: column)) { item in
                let lifted = moving?.entry == item.entry
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
                .gesture(lift(item.entry, item.isDue ? DateKey.due : DateKey.when, size: size))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.title), \(item.isDue ? "due" : "scheduled")")
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

    /// One piece of a bar in its lane, with the handle at each end: the leading one lifts the
    /// scheduled day, the trailing one the due day.
    private func piece(_ bar: MonthGrid.Bar, lifted: Bool, width: CGFloat, size: CGSize) -> some View {
        let pieceWidth = CGFloat(bar.columns) * width - 2 * Self.barInset
        let x = CGFloat(bar.from) * width + Self.barInset
        let y = Self.laneTop + CGFloat(bar.lane) * Self.laneHeight
        return BarPiece(bar: bar, lifted: lifted)
            .overlay(alignment: .leading) { handle(bar.entry, DateKey.when, size: size) }
            .overlay(alignment: .trailing) { handle(bar.entry, DateKey.due, size: size) }
            .frame(width: pieceWidth, height: Self.barHeight)
            .offset(x: x, y: y)
    }

    /// The strip at a bar's end that takes the drag: clear, over the piece, the width of a thumb.
    private func handle(_ entry: UUID, _ field: DateKey, size: CGSize) -> some View {
        Color.clear
            .frame(width: Self.handleWidth)
            .contentShape(Rectangle())
            .gesture(lift(entry, field, size: size))
            .accessibilityHidden(true)
    }

    /// The drag that lifts a day: the pointer and the day under it while it moves, the move when
    /// it lets go on a day, nothing when it lets go off the grid.
    private func lift(_ entry: UUID, _ field: DateKey, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .updating($holding) { _, state, _ in state = true }
            .onChanged { value in
                inHand = CalendarDrag(entry: entry, field: field, point: value.location, over: grid.month.day(under: value.location, in: size))
            }
            .onEnded { value in
                if let day = grid.month.day(under: value.location, in: size) { onMove(field, entry, day) }
                inHand = nil
            }
    }

    /// The day under the pointer, said beside it: the arrow or the flag and "14 Nov".
    private func dayChip(_ field: DateKey, _ day: Date) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
        return HStack(spacing: 5) {
            Image(systemName: field.symbol)
                .textRole(.caption)
                .foregroundStyle(Theme.leaf)
            Text(DayText.day(day, calendar: grid.month.calendar))
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
/// its thread's, since it is where it would land, not where it is.
struct BarPiece: View {
    let bar: MonthGrid.Bar
    var lifted: Bool = false

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
