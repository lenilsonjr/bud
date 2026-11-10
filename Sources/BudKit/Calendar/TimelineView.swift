#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The timeline: the scale across the top with a tick per column, the thread column on the
/// left with a header per thread and a row per bud, and the chart on the right, where a bud
/// with two days is a bar in its thread's colour and a bud with one day is a point. A header
/// folds its thread's rows and keeps a rail over the days they cover. The quiet shade marks the
/// weekends by the day and each month's first day by the week; today is a leaf line.
struct TimelineView: View {
    let timeline: Timeline
    /// Folds or opens the thread with this id.
    let toggle: (UUID) -> Void
    @Environment(\.compact) private var compact

    /// The board's measures: the scale, the thread column, the header and bud rows, the rail,
    /// the bar and the point.
    static let scaleHeight: CGFloat = 44
    static let labelWidth: CGFloat = 240
    static let compactLabelWidth: CGFloat = 150
    static let headerHeight: CGFloat = 34
    static let rowHeight: CGFloat = 30
    static let railHeight: CGFloat = 5
    static let barHeight: CGFloat = 20
    static let pointSize: CGFloat = 10
    /// A bar narrower than this keeps its title for the pointer alone.
    static let labelledBar: CGFloat = 48

    private var labelColumn: CGFloat { compact ? Self.compactLabelWidth : Self.labelWidth }

    var body: some View {
        VStack(spacing: 0) {
            scale
            MaybeScroll { rows }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background { chartBackground }
        }
        .background(Theme.surface)
        .clipped()
        .accessibilityIdentifier("calendar-timeline")
    }

    // MARK: The scale

    private var scale: some View {
        HStack(spacing: 0) {
            Text("Thread")
                .textRole(.eyebrow)
                .foregroundStyle(Theme.text3)
                .padding(.horizontal, 16)
                .frame(width: labelColumn, height: Self.scaleHeight, alignment: .leading)
                .overlay(alignment: .trailing) { Theme.line.frame(width: 1) }
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    ForEach(timeline.columns, id: \.day) { column in
                        let x = self.x(column.day, in: geo.size.width)
                        Theme.line
                            .frame(width: 1, height: Self.scaleHeight)
                            .offset(x: x)
                        Text(column.label)
                            .textStyle(TextStyle(typeface: .text, size: 11, weight: column.isToday ? 700 : 500))
                            .foregroundStyle(column.isToday ? Theme.leaf : Theme.text2)
                            .lineLimit(1)
                            .fixedSize()
                            .frame(height: Self.scaleHeight)
                            .offset(x: x + 5)
                            .accessibilityLabel(column.isToday ? "\(column.label), today" : column.label)
                    }
                }
            }
            .clipped()
        }
        .frame(height: Self.scaleHeight)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
    }

    // MARK: The rows

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(timeline.threads) { thread in
                header(thread)
                ForEach(thread.shownRows) { row in
                    self.row(row)
                }
            }
        }
    }

    /// A thread's header: its chevron, swatch and name on the left, its rail on the right.
    private func header(_ thread: Timeline.Thread) -> some View {
        HStack(spacing: 0) {
            Button { toggle(thread.id) } label: {
                HStack(spacing: 8) {
                    Image(systemName: thread.isCollapsed ? "chevron.right" : "chevron.down")
                        .textStyle(TextStyle(typeface: .text, size: 10, weight: 600))
                        .foregroundStyle(Theme.text3)
                        .frame(width: 12)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(thread.tone.tone))
                        .frame(width: 10, height: 10)
                    Text(thread.title)
                        .textStyle(TextStyle(typeface: .text, size: 13, weight: 600))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(width: labelColumn, height: Self.headerHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(thread.isCollapsed ? "Open \(thread.title)" : "Fold \(thread.title)")
            .accessibilityLabel(thread.title)
            .accessibilityValue(thread.isCollapsed ? "Folded" : "Open")
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(thread.tone.tone))
                    .opacity(0.55)
                    .frame(width: max(Self.railHeight, span(thread.from, thread.to, in: geo.size.width)), height: Self.railHeight)
                    .offset(x: x(thread.from, in: geo.size.width), y: (Self.headerHeight - Self.railHeight) / 2)
                    .accessibilityHidden(true)
            }
            .frame(height: Self.headerHeight)
            .clipped()
        }
        .frame(height: Self.headerHeight)
    }

    /// A bud's row: its icon and name on the left, its bar or point on the right.
    private func row(_ row: Timeline.Row) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: row.isDone ? "checkmark.circle" : row.isRoutine ? "repeat" : "circle")
                    .textStyle(TextStyle(typeface: .text, size: 11, weight: 500))
                    .foregroundStyle(row.isDone ? Theme.leaf : Theme.text3)
                    .frame(width: 12)
                Text(row.title)
                    .textStyle(TextStyle(typeface: .text, size: 12, weight: 400))
                    .foregroundStyle(row.isDone ? Theme.text3 : Theme.text)
                    .strikethrough(row.isDone, color: Theme.text3)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 34)
            .padding(.trailing, 14)
            .frame(width: labelColumn, height: Self.rowHeight)
            .accessibilityElement(children: .combine)
            GeometryReader { geo in
                if row.isPoint {
                    point(row, in: geo.size.width)
                } else {
                    bar(row, in: geo.size.width)
                }
            }
            .frame(height: Self.rowHeight)
            .clipped()
        }
        .frame(height: Self.rowHeight)
    }

    /// A bar from the bud's first day to its last, flat at an edge it runs past, faded when done.
    private func bar(_ row: Timeline.Row, in width: CGFloat) -> some View {
        let radius = Radius.chip
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: row.startsBefore ? 0 : radius, bottomLeadingRadius: row.startsBefore ? 0 : radius,
            bottomTrailingRadius: row.endsAfter ? 0 : radius, topTrailingRadius: row.endsAfter ? 0 : radius,
            style: .continuous
        )
        let barWidth = max(Self.pointSize, span(row.from, row.to, in: width))
        return HStack(spacing: 0) {
            if barWidth >= Self.labelledBar {
                Text(row.title)
                    .textStyle(TextStyle(typeface: .text, size: 11, weight: 600))
                    .foregroundStyle(Theme.text)
                    .strikethrough(row.isDone, color: Theme.text3)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
            }
        }
        .frame(width: barWidth, height: Self.barHeight, alignment: .leading)
        .background(Color(row.tone.soft), in: shape)
        .overlay(shape.stroke(Color(row.tone.tone), lineWidth: 1))
        .clipShape(shape)
        .opacity(row.isDone ? 0.5 : 1)
        .offset(x: x(row.from, in: width), y: (Self.rowHeight - Self.barHeight) / 2)
        .help(row.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.title), \(row.days == 1 ? "one day" : "\(row.days) days")")
    }

    /// A point in the middle of the bud's day, its name beside it.
    private func point(_ row: Timeline.Row, in width: CGFloat) -> some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color(row.tone.tone))
                .frame(width: Self.pointSize, height: Self.pointSize)
            Text(row.title)
                .textStyle(TextStyle(typeface: .text, size: 11, weight: 400))
                .foregroundStyle(row.isDone ? Theme.text3 : Theme.text2)
                .strikethrough(row.isDone, color: Theme.text3)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(height: Self.rowHeight)
        .offset(x: x(row.from, in: width) + dayWidth(in: width) / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.title), \(row.isDue ? "due" : "scheduled")")
    }

    // MARK: The chart

    /// Behind the rows: the shades, the grid line at each column, the thread column's edge and
    /// today's line, over the whole height.
    private var chartBackground: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: labelColumn)
                .overlay(alignment: .trailing) { Theme.line.frame(width: 1) }
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    ForEach(timeline.shaded, id: \.self) { days in
                        Theme.sidebar
                            .frame(width: span(days.lowerBound, days.upperBound, in: geo.size.width), height: geo.size.height)
                            .offset(x: x(days.lowerBound, in: geo.size.width))
                    }
                    ForEach(timeline.columns, id: \.day) { column in
                        Theme.line
                            .frame(width: 1, height: geo.size.height)
                            .offset(x: x(column.day, in: geo.size.width))
                    }
                    if let today = timeline.today {
                        Theme.leaf
                            .frame(width: 2, height: geo.size.height)
                            .offset(x: x(today, in: geo.size.width) + dayWidth(in: geo.size.width) / 2 - 1)
                            .accessibilityLabel("Today")
                    }
                }
            }
            .clipped()
        }
        .accessibilityHidden(true)
    }

    /// Where a day starts across the chart.
    private func x(_ day: Int, in width: CGFloat) -> CGFloat {
        CGFloat(timeline.position(ofDay: day)) * width
    }

    private func dayWidth(in width: CGFloat) -> CGFloat {
        width / CGFloat(timeline.days)
    }

    /// The width from the start of `from` to the end of `to`.
    private func span(_ from: Int, _ to: Int, in width: CGFloat) -> CGFloat {
        x(to + 1, in: width) - x(from, in: width)
    }
}
#endif
