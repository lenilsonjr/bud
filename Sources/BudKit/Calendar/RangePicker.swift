#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The custom range picker, over the Custom segment: this year and the next as rows of month
/// chips, the first and last picked in the leaf and the months between them soft; the presets
/// under a line, each shown at once; and the hint with the Show button, which shows the two
/// months picked. The taps live in `RangePick`; the range chosen goes through the store.
struct RangePicker: View {
    @ObservedObject var store: BudStore
    /// Called once a range is shown, so the popover closes.
    var onDone: () -> Void = {}
    @State private var pick: RangePick

    static let width: CGFloat = 340
    static let chipHeight: CGFloat = 28

    init(store: BudStore, onDone: @escaping () -> Void = {}) {
        self._store = ObservedObject(wrappedValue: store)
        self.onDone = onDone
        self._pick = State(initialValue: RangePick(store.calendarState.custom))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(RangePick.years(now: store.now, holding: pick.range ?? store.calendarState.custom, calendar: store.calendar), id: \.self) { year in
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(year))
                        .textStyle(TextStyle(typeface: .text, size: 10, weight: 700))
                        .foregroundStyle(Theme.text3)
                    ForEach([1...6, 7...12], id: \.lowerBound) { months in
                        HStack(spacing: 0) {
                            ForEach(months, id: \.self) { month in
                                chip(YearMonth(year: year, month: month))
                            }
                        }
                    }
                }
            }
            Theme.line.frame(height: 1)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(store.rangePresets) { preset in
                    Button {
                        show(preset.range)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: preset.symbol)
                                .textRole(.caption)
                                .foregroundStyle(Theme.text3)
                                .frame(width: 13)
                                .accessibilityHidden(true)
                            Text(preset.title)
                                .textStyle(TextStyle(typeface: .text, size: 13, weight: 400))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                        .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(preset.range.title(calendar: store.calendar))
                }
            }
            HStack(spacing: 8) {
                Text("Pick a first and a last month")
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
                Spacer(minLength: 8)
                Button(pick.showLine) {
                    if let range = pick.range { show(range) }
                }
                .buttonStyle(.budPrimary)
                .disabled(pick.range == nil)
                .accessibilityIdentifier("range-show")
            }
        }
        .padding(16)
        .frame(width: Self.width)
        .accessibilityIdentifier("range-picker")
    }

    /// One month to tap: the first or last in the leaf, one between them soft, the rest plain.
    private func chip(_ month: YearMonth) -> some View {
        let end = pick.isEnd(month)
        let between = pick.isBetween(month)
        return Button {
            pick.tap(month)
        } label: {
            Text(month.text("MMM", calendar: store.calendar))
                .textStyle(TextStyle(typeface: .text, size: 12, weight: end || between ? 600 : 500))
                .foregroundStyle(end ? Theme.onLeaf : between ? Theme.text : Theme.text2)
                .frame(maxWidth: .infinity)
                .frame(height: Self.chipHeight)
                .background(between ? Theme.leafSoft : .clear)
                .background(end ? Theme.leaf : .clear, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(month.text("MMMM yyyy", calendar: store.calendar))
        .accessibilityAddTraits(end ? .isSelected : [])
    }

    private func show(_ range: CustomRange) {
        store.pickRange(range)
        pick = RangePick(range)
        onDone()
    }
}
#endif
