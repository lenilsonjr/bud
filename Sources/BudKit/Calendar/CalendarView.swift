#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The Calendar view: the bar across its top with the range's title, a month back and forward,
/// Today, the range segments and the Calendar or Timeline switch; the Threads and Show column on
/// the left; and the grid for the range on the right. The month grid is built; the other ranges
/// and the timeline say they are coming in the grid's place.
struct CalendarView: View {
    @ObservedObject var store: BudStore
    @Environment(\.compact) private var compact

    var body: some View {
        VStack(spacing: 0) {
            head
            HStack(spacing: 0) {
                if !compact { ThreadsColumn(store: store) }
                main
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
    }

    /// The title and the switches on one row where they fit; the switches under the title on a
    /// phone, or wherever one row would clip them.
    @ViewBuilder private var head: some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 8) {
                    titleRow
                    switches
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        titleRow
                        Spacer(minLength: 10)
                        switches
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        titleRow
                        switches
                    }
                }
                .padding(.horizontal, 20)
                .frame(minHeight: 60)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
    }

    private var titleRow: some View {
        HStack(spacing: 10) {
            Text(store.calendar.range.title(for: store.calendarFocus, calendar: store.dateCalendar))
                .textStyle(TextStyle(typeface: .display, size: 24, weight: 500))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .accessibilityIdentifier("calendar-title")
            HStack(spacing: 2) {
                arrow("chevron.left", label: "Previous month") { store.shiftCalendar(months: -1) }
                arrow("chevron.right", label: "Next month") { store.shiftCalendar(months: 1) }
            }
            Button("Today") { store.calendarToday() }
                .buttonStyle(.budSecondary)
                .help("Back to today")
        }
    }

    private var switches: some View {
        HStack(spacing: 10) {
            Segmented(selection: $store.calendar.range, options: CalendarRange.allCases, label: { $0.rawValue }, icon: { $0 == .custom ? "calendar.badge.clock" : nil })
                .accessibilityIdentifier("calendar-range")
            Segmented(selection: $store.calendar.layout, options: CalendarLayout.allCases, label: { $0.rawValue }, icon: { $0 == .calendar ? "calendar" : "calendar.day.timeline.left" })
                .accessibilityIdentifier("calendar-layout")
        }
    }

    private func arrow(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .textRole(.label)
                .foregroundStyle(Theme.text2)
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: Radius.iconButton, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    /// The grid for the range and layout chosen, or the line saying it is coming.
    @ViewBuilder private var main: some View {
        Group {
            if store.calendar.layout == .timeline {
                quiet(store.calendar.layout.comingLine)
            } else if store.calendar.range == .month {
                MonthGridView(grid: store.monthGrid)
            } else {
                quiet(store.calendar.range.comingLine)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func quiet(_ line: String) -> some View {
        Text(line)
            .textRole(.body)
            .foregroundStyle(Theme.text3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
    }
}

/// The left column: every thread with its colour, each a tick that hides its buds, and the
/// four Show switches.
struct ThreadsColumn: View {
    @ObservedObject var store: BudStore

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            eyebrow("Threads")
            ForEach(store.calendarThreads) { thread in
                let on = store.calendar.shows(thread: thread.id)
                Button { store.toggleThread(thread.id) } label: {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color(thread.tone.tone))
                            .frame(width: 10, height: 10)
                            .opacity(on ? 1 : 0.35)
                        Text(thread.title)
                            .textStyle(TextStyle(typeface: .text, size: 13, weight: 400))
                            .foregroundStyle(on ? Theme.text : Theme.text3)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(on ? "Hide \(thread.title)" : "Show \(thread.title)")
                .accessibilityLabel(thread.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            eyebrow("Show").padding(.top, 12)
            ForEach(CalendarShow.allCases, id: \.self) { show in
                let on = store.calendar.shows(show)
                Button { store.toggle(show) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: Self.symbol(of: show))
                            .textRole(.caption)
                            .foregroundStyle(on ? Theme.text2 : Theme.text3)
                            .frame(width: 13)
                        Text(show.rawValue)
                            .textStyle(TextStyle(typeface: .text, size: 13, weight: 400))
                            .foregroundStyle(Theme.text)
                        Spacer(minLength: 8)
                        SwitchKnob(on: on)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(on ? "Hide \(show.rawValue.lowercased())" : "Show \(show.rawValue.lowercased())")
                .accessibilityLabel(show.rawValue)
                .accessibilityValue(on ? "On" : "Off")
                .accessibilityAddTraits(.isToggle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .frame(width: 200)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) { Theme.line.frame(width: 1) }
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text)
            .textRole(.eyebrow)
            .foregroundStyle(Theme.text3)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
    }

    static func symbol(of show: CalendarShow) -> String {
        switch show {
        case .when: return "calendar"
        case .due: return "flag"
        case .routines: return "repeat"
        case .done: return "checkmark.circle"
        }
    }
}

/// The small switch at the end of a Show row: the leaf fill with the knob to the right when on,
/// raised with a grey knob to the left when off.
struct SwitchKnob: View {
    let on: Bool

    var body: some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule(style: .continuous)
                .fill(on ? Theme.leafFill : Theme.raised)
            Capsule(style: .continuous)
                .stroke(on ? Color.clear : Theme.lineStrong, lineWidth: 1)
            Circle()
                .fill(on ? Theme.onLeaf : Theme.text3)
                .frame(width: 14, height: 14)
                .padding(2)
        }
        .frame(width: 30, height: 18)
        .accessibilityHidden(true)
    }
}
#endif
