#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The year, or a custom range: small months in rows of four, each its name, the weekday
/// letters and six rows of days. A day crossed by a long bud is shaded in the thread's soft
/// tone, a day with a bud on it carries a dot, and today sits in the leaf. Three rows fit the
/// frame; a longer custom range scrolls.
struct YearView: View {
    let grid: YearGrid

    var body: some View {
        MaybeScroll {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(grid.rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 24) {
                        ForEach(row, id: \.month) { month in
                            SmallMonthView(month: month, weekdays: grid.weekdays)
                        }
                        // A short last row keeps its months the width of a full one.
                        ForEach(row.count..<YearGrid.columns, id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity).frame(height: 1)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface)
        .accessibilityIdentifier("calendar-year")
    }
}

/// One small month: the name in the leaf for this month, dim for one gone by; the letters; the
/// days, each a number over a dot, with the cell shaded where a long bud crosses it.
struct SmallMonthView: View {
    let month: SmallMonth
    let weekdays: [String]

    /// The board's measures: the row, the number's pill and the dot under it.
    static let rowHeight: CGFloat = 24
    static let numberSize = CGSize(width: 18, height: 16)
    static let dotSize: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(month.title)
                .textStyle(TextStyle(typeface: .text, size: 17, weight: 500))
                .foregroundStyle(month.isCurrent ? Theme.leaf : month.isPast ? Theme.text2 : Theme.text)
                .lineLimit(1)
            HStack(spacing: 0) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .textStyle(TextStyle(typeface: .text, size: 9, weight: 700))
                        .foregroundStyle(Theme.text3)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            ForEach(Array(month.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            cell(day)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .frame(height: Self.rowHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(month.title)
    }

    private func cell(_ day: SmallMonth.Day) -> some View {
        VStack(spacing: 1) {
            Text("\(day.number)")
                .textStyle(TextStyle(typeface: .text, size: 10, weight: day.isToday ? 700 : 500))
                .foregroundStyle(day.isToday ? Theme.onLeaf : day.isPast ? Theme.text3 : Theme.text)
                .frame(width: Self.numberSize.width, height: Self.numberSize.height)
                .background(day.isToday ? Theme.leaf : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Circle()
                .fill(day.dot.map { Color($0.tone) } ?? .clear)
                .frame(width: Self.dotSize, height: Self.dotSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(day.shade.map { Color($0.soft) } ?? .clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(day))
    }

    /// "3, today, a bud", as a reader hears a day.
    private func label(_ day: SmallMonth.Day) -> String {
        var parts = ["\(day.number)"]
        if day.isToday { parts.append("today") }
        if day.dot != nil { parts.append("a bud") }
        if day.shade != nil { parts.append("in a long bud") }
        return parts.joined(separator: ", ")
    }
}
#endif
