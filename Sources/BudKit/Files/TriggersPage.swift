#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The Library's Triggers: each stamps a Warehouse template into a place on a schedule. A trigger
/// card says what it stamps, the rule with its next date and place, whether it is enabled, and
/// its log of firings.
struct TriggersPage: View {
    @ObservedObject var store: BudStore
    @State private var making = false

    var body: some View {
        MaybeScroll {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LIBRARY")
                            .textRole(.eyebrow)
                            .foregroundStyle(Theme.leaf)
                        Text("Triggers")
                            .textRole(.title)
                            .foregroundStyle(Theme.text)
                        Text(store.triggers.count == 1 ? "1 trigger" : "\(store.triggers.count) triggers")
                            .textRole(.caption)
                            .foregroundStyle(Theme.text3)
                    }
                    Spacer()
                    Button { making = true } label: { BudButtonLabel(title: "New trigger", systemImage: "plus") }
                        .buttonStyle(.budPrimary)
                        .disabled(store.tree.templates().isEmpty)
                        .accessibilityIdentifier("new-trigger")
                }
                if store.triggers.isEmpty {
                    Text(store.tree.templates().isEmpty ? TriggerWords.noTemplates : TriggerWords.empty)
                        .textRole(.body)
                        .foregroundStyle(Theme.text3)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(store.triggers) { trigger in
                            TriggerCard(store: store, trigger: trigger)
                        }
                    }
                }
            }
            .pageColumn()
        }
        .sheet(isPresented: $making) {
            NewTriggerSheet(store: store, close: { making = false })
                .frame(width: ModalMetrics.width - 2 * ModalMetrics.padding)
                .padding(ModalMetrics.padding)
                .background(Theme.raised)
        }
    }
}

struct TriggerCard: View {
    @ObservedObject var store: BudStore
    let trigger: Trigger

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trigger.name)
                        .textRole(.label)
                        .foregroundStyle(Theme.text)
                    Text(TriggerText.stamps(trigger))
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                }
                Spacer()
                NeutralTag(trigger.enabled ? "Enabled" : "Paused")
            }
            Text(TriggerText.rule(trigger, now: store.now))
                .textRole(.body)
                .foregroundStyle(Theme.text2)
            if !trigger.log.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(trigger.log.prefix(5), id: \.self) { firing in
                        Text(TriggerText.firing(firing))
                            .textRole(.caption)
                            .foregroundStyle(firing.skipped == nil ? Theme.text3 : Theme.rose)
                    }
                }
            }
            Divider()
            HStack(spacing: 8) {
                Button(trigger.enabled ? "Pause" : "Enable") {
                    var changed = trigger
                    changed.enabled.toggle()
                    store.save(changed)
                }
                .buttonStyle(.budGhost)
                Spacer()
                Button("Delete", role: .destructive) { store.deleteTrigger(trigger.id) }
                    .buttonStyle(.budGhost)
            }
        }
        .padding(14)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Theme.line))
    }
}

/// A new trigger: its name, the template it stamps, how often and when, and where copies go.
struct NewTriggerSheet: View {
    @ObservedObject var store: BudStore
    let close: () -> Void

    @State private var name = ""
    @State private var template: String?
    @State private var every: Trigger.Rule.Every = .week
    @State private var weekday = 2
    @State private var day = 1
    @State private var time = Calendar.current.date(from: DateComponents(hour: 9)) ?? Date()
    @State private var into: UUID = rootID

    var body: some View {
        DialogBody(title: "New trigger", text: TriggerWords.sheet) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Name, as in Monday review", text: $name)
                    .textFieldStyle(.roundedBorder)
                Picker("Template", selection: $template) {
                    ForEach(store.tree.templates()) { bud in
                        Text(bud.text).tag(Optional(bud.text))
                    }
                }
                Segmented(selection: $every, options: Trigger.Rule.Every.allCases) { TriggerWords.every($0) }
                switch every {
                case .day: EmptyView()
                case .week:
                    Picker("On", selection: $weekday) {
                        ForEach(1...7, id: \.self) { Text(TriggerText.weekdays[$0 - 1]).tag($0) }
                    }
                case .month:
                    Picker("On the", selection: $day) {
                        ForEach(1...28, id: \.self) { Text(TriggerText.ordinal($0)).tag($0) }
                    }
                }
                DatePicker("At", selection: $time, displayedComponents: .hourAndMinute)
                Picker("Into", selection: $into) {
                    ForEach(places, id: \.self) { Text(store.tree.title(of: $0)).tag($0) }
                }
            }
        } actions: {
            Button(action: close) { BudButtonLabel(title: "Cancel") }
                .buttonStyle(.budSecondary)
                .keyboardShortcut(.cancelAction)
            Button(action: make) { BudButtonLabel(title: "Make trigger") }
                .buttonStyle(.budPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(template == nil)
        }
        .onAppear { template = template ?? store.tree.templates().first?.text }
    }

    private var places: [UUID] {
        [rootID] + store.tree.children(of: rootID).filter { !$0.isDone }.map(\.id) + [inboxID]
    }

    private func make() {
        guard let template else { return }
        let clock = Calendar.current.dateComponents([.hour, .minute], from: time)
        let rule = Trigger.Rule(every: every, hour: clock.hour ?? 9, minute: clock.minute ?? 0, weekday: weekday, day: day)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var trigger = Trigger(
            name: trimmed.isEmpty ? template : trimmed, template: template, into: store.triggerPath(of: into),
            intoName: store.tree.title(of: into), rule: rule
        )
        // The device that made it fires it, so the first occurrence is not stamped everywhere.
        trigger.holder = BudStore.deviceID
        trigger.holderName = BudStore.deviceName
        store.save(trigger)
        close()
    }
}
#endif

/// The words of the Triggers page that are not a card's, kept pure for a test on any platform.
public enum TriggerWords {
    public static let empty = "No triggers yet. A trigger stamps a template into a place every day, week or month."
    public static let noTemplates = "Triggers stamp templates. Keep a bud as a template in the Warehouse first."
    public static let sheet = "One device fires it at the time; another takes over if that one is away for an hour."

    public static func every(_ every: Trigger.Rule.Every) -> String {
        switch every {
        case .day: return "Daily"
        case .week: return "Weekly"
        case .month: return "Monthly"
        }
    }
}
