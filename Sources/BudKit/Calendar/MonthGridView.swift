#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The month: the weekday names over six rows of seven cells, each with its number, room for
/// the bars crossing it and its items. Bars are drawn over their row, one piece per week, in
/// their thread's colour, and clipped to the row; lanes the row has no room for become a
/// "+2 more" line in each cell they cross.
struct MonthGridView: View {
    let grid: MonthGrid

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

    /// How many lanes a row of this height holds above the room for one line.
    static func lanes(fitting height: CGFloat) -> Int {
        max(0, Int((height - laneTop - itemRoom - cellPadding) / laneHeight))
    }

    var body: some View {
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
                                    cell(row: row, column: column, fits: fits)
                                        .frame(width: width, height: height)
                                }
                            }
                            ForEach(grid.bars(inRow: row, fitting: fits)) { bar in
                                BarPiece(bar: bar)
                                    .frame(width: CGFloat(bar.columns) * width - 2 * Self.barInset, height: Self.barHeight)
                                    .offset(x: CGFloat(bar.from) * width + Self.barInset, y: Self.laneTop + CGFloat(bar.lane) * Self.laneHeight)
                            }
                        }
                        .frame(width: geo.size.width, height: height)
                        .clipped()
                    }
                }
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

    private func cell(row: Int, column: Int, fits: Int) -> some View {
        let day = grid.month.weeks[row][column]
        let quiet = !day.inMonth || day.isWeekend
        let room = min(grid.lanes[row], fits)
        let more = grid.overflow(row: row, column: column, fitting: fits)
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
            ForEach(grid.items(row: row, column: column)) { item in
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
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.title), \(item.isDue ? "due" : "scheduled")")
            }
            Spacer(minLength: 0)
        }
        .padding(Self.cellPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(quiet ? Theme.sidebar : .clear)
        .overlay(alignment: .trailing) { Theme.line.frame(width: 1) }
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
        .clipped()
    }
}

/// One week's piece of a bar: the thread's soft fill and line, an arrow where the bud is
/// scheduled, a flag and "due 4 Dec" where it is due, the title between. A piece holding both
/// days leads with the arrow and ends with the flag.
struct BarPiece: View {
    let bar: MonthGrid.Bar

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
        .overlay(shape.stroke(tone, lineWidth: 1))
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
#endif
