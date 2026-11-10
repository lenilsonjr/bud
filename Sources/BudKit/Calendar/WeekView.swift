#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The week: the seven days across the top, today's number in a leaf circle; the all-day row
/// under them, its bars running across the columns they cover; the hours below, with each
/// day's blocks in its column, the weekend tinted, and the now line across today's column.
struct WeekView: View {
    let plan: CalendarDays

    /// The board's measures: the hour labels' column and the day heads' height.
    static let gutter: CGFloat = 56
    static let headHeight: CGFloat = 52

    var body: some View {
        VStack(spacing: 0) {
            heads
            allDay
            HoursView(plan: plan, gutter: Self.gutter, labelInset: 12)
        }
        .background(Theme.surface)
        .accessibilityIdentifier("calendar-week")
    }

    private var heads: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.gutter)
            ForEach(plan.days, id: \.date) { day in
                VStack(alignment: .leading, spacing: 1) {
                    Text(day.weekday)
                        .textStyle(TextStyle(typeface: .text, size: 10, weight: 700, tracking: 1.2))
                        .foregroundStyle(day.isToday ? Theme.leaf : Theme.text3)
                    Text("\(day.number)")
                        .textStyle(TextStyle(typeface: .text, size: 14, weight: 600))
                        .foregroundStyle(day.isToday ? Theme.onLeaf : Theme.text)
                        .frame(width: 24, height: 24)
                        .background(day.isToday ? Theme.leaf : .clear, in: Circle())
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(day.isToday ? "Today, \(day.weekday) \(day.number)" : "\(day.weekday) \(day.number)")
            }
        }
        .frame(height: Self.headHeight)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
    }

    /// The bars over the columns they cover, in their lanes; the row grows with the lanes.
    private var allDay: some View {
        let height = max(AllDayRow.minHeight, 12 + CGFloat(plan.lanes) * AllDayRow.laneHeight)
        return GeometryReader { geo in
            let columnWidth = (geo.size.width - Self.gutter) / CGFloat(plan.days.count)
            ZStack(alignment: .topLeading) {
                Text("All day")
                    .textRole(.eyebrow)
                    .foregroundStyle(Theme.text3)
                    .offset(x: 12, y: 8)
                ForEach(plan.bars) { bar in
                    AllDayBar(bar: bar)
                        .frame(width: CGFloat(bar.columns) * columnWidth - 2 * AllDayRow.inset, height: AllDayRow.barHeight)
                        .offset(x: Self.gutter + CGFloat(bar.from) * columnWidth + AllDayRow.inset, y: 6 + CGFloat(bar.lane) * AllDayRow.laneHeight)
                }
            }
        }
        .frame(height: height)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("All day")
    }
}
#endif
