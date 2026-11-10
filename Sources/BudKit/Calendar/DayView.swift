#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The day: the all-day row on top, its spans and dateless-hour buds as chips flowing across
/// the row; the hours below, from 07:00, with the blocks placed by their minutes and the now
/// line where the clock is.
struct DayView: View {
    let plan: CalendarDays

    /// The board's measures: the hour labels' column, and how wide the blocks keep to so a
    /// title reads as one line.
    static let gutter: CGFloat = 64
    static let blockWidth: CGFloat = 560

    var body: some View {
        VStack(spacing: 0) {
            allDay
            HoursView(plan: plan, gutter: Self.gutter, labelInset: 16, blockWidth: Self.blockWidth)
        }
        .background(Theme.surface)
        .accessibilityIdentifier("calendar-day")
    }

    /// The row of chips, wrapping when the day has more than one line's worth.
    private var allDay: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("All day")
                .textRole(.eyebrow)
                .foregroundStyle(Theme.text3)
                .padding(.leading, 16)
                .padding(.top, 8)
                .frame(width: AllDayRow.chipLeft, alignment: .topLeading)
            ChipFlow(spacing: 4) {
                ForEach(plan.bars) { bar in
                    AllDayBar(bar: bar)
                        .frame(height: AllDayRow.barHeight)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minHeight: AllDayRow.minHeight, alignment: .top)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("All day")
    }
}

/// The all-day row's measures, shared by the day and the week.
enum AllDayRow {
    static let minHeight: CGFloat = 56
    static let barHeight: CGFloat = 20
    static let laneHeight: CGFloat = 24
    static let inset: CGFloat = 4
    /// Where the day's chips start: past the eyebrow.
    static let chipLeft: CGFloat = 80
}

/// One bar of the all-day row: the thread's soft fill and line, an arrow where the bud is
/// scheduled, a flag where it is due, the label between.
struct AllDayBar: View {
    let bar: CalendarDays.Bar

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
            Text(bar.label)
                .textStyle(TextStyle(typeface: .text, size: 11, weight: 600))
                .foregroundStyle(bar.isDone ? Theme.text3 : Theme.text)
                .strikethrough(bar.isDone, color: Theme.text3)
                .lineLimit(1)
            if bar.columns > 1 { Spacer(minLength: 0) }
            if bar.starts && bar.ends {
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
        .accessibilityLabel(bar.label)
    }

    /// The arrow where the bud is scheduled; else the flag where it is due; else nothing.
    private var leading: String? {
        if bar.starts { return "arrow.right" }
        return bar.ends ? "flag" : nil
    }
}

/// The hours: the labels down the left, a line each, the columns with their blocks, and the
/// now line. The hours fill the height they are given, and scroll when that is less than they
/// need to read.
struct HoursView: View {
    let plan: CalendarDays
    /// The labels' column on the left.
    let gutter: CGFloat
    /// Where a label starts inside the gutter.
    let labelInset: CGFloat
    /// How wide a column's blocks keep to; nil to fill the column.
    var blockWidth: CGFloat? = nil

    static let topInset: CGFloat = 10
    static let minHourHeight: CGFloat = 44
    static let blockInset: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let hourHeight = max(Self.minHourHeight, (geo.size.height - 2 * Self.topInset) / CGFloat(plan.hourCount))
            let height = hourHeight * CGFloat(plan.hourCount) + 2 * Self.topInset
            MaybeScroll {
                grid(width: geo.size.width, hourHeight: hourHeight)
                    .frame(width: geo.size.width, height: height)
            }
        }
        .clipped()
    }

    private func grid(width: CGFloat, hourHeight: CGFloat) -> some View {
        let columnWidth = (width - gutter) / CGFloat(plan.days.count)
        let span = hourHeight * CGFloat(plan.hourCount)
        let height = span + 2 * Self.topInset
        func y(_ minutes: Int) -> CGFloat { Self.topInset + CGFloat(plan.position(ofMinutes: minutes)) * span }
        return ZStack(alignment: .topLeading) {
            ForEach(Array(plan.days.enumerated()), id: \.offset) { index, day in
                if day.isWeekend {
                    Theme.sidebar.opacity(0.6)
                        .frame(width: columnWidth, height: height)
                        .offset(x: gutter + CGFloat(index) * columnWidth)
                }
            }
            ForEach(Array(plan.hours.enumerated()), id: \.offset) { index, label in
                let top = Self.topInset + CGFloat(index) * hourHeight
                Theme.line.frame(width: width - gutter, height: 1).offset(x: gutter, y: top)
                Text(label)
                    .textStyle(TextStyle(typeface: .text, size: 10, weight: 400))
                    .foregroundStyle(Theme.text3)
                    .offset(x: labelInset, y: top - 7)
            }
            Theme.line.frame(width: width - gutter, height: 1).offset(x: gutter, y: Self.topInset + span)
            ForEach(1..<max(1, plan.days.count), id: \.self) { index in
                Theme.line.frame(width: 1, height: height).offset(x: gutter + CGFloat(index) * columnWidth)
            }
            ForEach(plan.blocks) { block in
                let room = min(columnWidth, blockWidth ?? columnWidth) - 2 * Self.blockInset
                let laneWidth = room / CGFloat(block.lanes)
                let top = y(block.start)
                let tall = max(14, y(block.end) - top - 2)
                HourBlock(block: block, tall: tall)
                    .frame(width: max(10, laneWidth - 2), height: tall)
                    .offset(x: gutter + CGFloat(block.column) * columnWidth + Self.blockInset + CGFloat(block.lane) * laneWidth, y: top + 1)
            }
            if let now = plan.now {
                let across = plan.days.count == 1 ? width - gutter : columnWidth
                HStack(spacing: 0) {
                    Circle().fill(Theme.leaf).frame(width: 8, height: 8)
                    Theme.leaf.frame(height: 1.5)
                }
                .frame(width: across + 8, height: 8)
                .offset(x: gutter + CGFloat(now.column) * columnWidth - 8, y: y(now.minutes) - 4)
                .accessibilityLabel("Now, \(CalendarDays.time(now.minutes))")
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }
}

/// A bud in the hours: the thread's soft fill and line, the title over the time where the
/// block is tall enough, beside it where it is not.
struct HourBlock: View {
    let block: CalendarDays.Block
    let tall: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
        let tone = Color(block.tone.tone)
        Group {
            if tall >= 34 {
                VStack(alignment: .leading, spacing: 1) {
                    title
                    time
                }
            } else {
                HStack(spacing: 5) {
                    title
                    time
                }
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(block.tone.soft), in: shape)
        .overlay(shape.stroke(tone, lineWidth: 1))
        .clipShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(block.title), \(block.isDue ? "due " : "")\(block.time)")
    }

    private var title: some View {
        Text(block.title)
            .textStyle(TextStyle(typeface: .text, size: 11, weight: 600))
            .foregroundStyle(block.isDone ? Theme.text3 : Theme.text)
            .strikethrough(block.isDone, color: Theme.text3)
            .lineLimit(1)
    }

    private var time: some View {
        Text(block.time)
            .textStyle(TextStyle(typeface: .text, size: 10, weight: 400))
            .foregroundStyle(Theme.text2)
            .lineLimit(1)
            .fixedSize()
    }
}

/// Chips in reading order, wrapping to the next line where the row runs out.
struct ChipFlow: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let frames = place(subviews, in: width)
        let height = frames.map { $0.maxY }.max() ?? 0
        return CGSize(width: proposal.width ?? (frames.map { $0.maxX }.max() ?? 0), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, place(subviews, in: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func place(_ subviews: Subviews, in width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var line: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let fit = min(size.width, width)
            if x > 0, x + fit > width {
                x = 0
                y += line + spacing
                line = 0
            }
            frames.append(CGRect(x: x, y: y, width: fit, height: size.height))
            x += fit + spacing
            line = max(line, size.height)
        }
        return frames
    }
}
#endif
