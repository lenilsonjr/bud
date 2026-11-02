#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The Inbox (B3): the workbench. Captures grouped by day, newest first, each with its source
/// and time, a tag for raw or enriched, Enrich and Move to…. Nothing here gets sorted for you;
/// filing is the last step, by Move to… or by dragging a row onto a bud in the sidebar.
struct InboxPage: View {
    @ObservedObject var store: BudStore
    @State private var filter: InboxFilter = .all
    @State private var moving: Bud? = nil

    var body: some View {
        let count = store.tree.inbox().count
        let groups = store.tree.inboxGroups(filter)
        MaybeScroll {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PLACE")
                        .textRole(.eyebrow)
                        .foregroundStyle(Theme.leaf)
                    Text("Inbox")
                        .textRole(.title)
                        .foregroundStyle(Theme.text)
                    Text(count == 1 ? "1 capture" : "\(count) captures")
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                }
                Segmented(selection: $filter, options: InboxFilter.allCases) { $0.rawValue }
                if groups.isEmpty {
                    Text(count == 0 ? "Nothing waiting. Capture a line and it lands here." : "Nothing \(filter.rawValue.lowercased()) right now.")
                        .textRole(.body)
                        .foregroundStyle(Theme.text3)
                } else {
                    ForEach(groups, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.label.uppercased())
                                .textRole(.eyebrow)
                                .foregroundStyle(Theme.text3)
                                .padding(.bottom, 4)
                            ForEach(group.buds) { bud in
                                row(bud)
                            }
                        }
                    }
                }
                Text("Nothing here gets sorted for you. Drag a bud onto any thread when it's ready; filing is the last step.")
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
                    .padding(.top, 8)
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .sheet(item: $moving) { bud in MoveToPicker(store: store, bud: bud) }
    }

    private func row(_ bud: Bud) -> some View {
        let inside = store.tree.children(of: bud.id).count
        return HStack(alignment: .top, spacing: 8) {
            if bud.isTodo {
                Button { store.toggle(bud.id) } label: {
                    KindMark(bud: bud, style: CardStyle.chip(for: bud, lit: false))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            } else {
                KindMark(bud: bud, style: CardStyle.chip(for: bud, lit: false))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(bud.text)
                    .textRole(.body)
                    .strikethrough(bud.isDone)
                    .foregroundStyle(bud.isDone ? Theme.text3 : Theme.text)
                Text(caption(bud))
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
            }
            Spacer()
            tag(inside == 0 ? "raw" : (inside == 1 ? "1 inside" : "\(inside) inside"))
            Button("Enrich") { store.modal = .add(parent: bud.id) }
                .buttonStyle(.bordered)
            Button("Move to…") { moving = bud }
                .buttonStyle(.bordered)
        }
        .textRole(.label)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .draggable(bud.id.uuidString)
    }

    /// "from mac · 09:14"; a capture made by hand with no source shows the time alone.
    private func caption(_ bud: Bud) -> String {
        let time = bud.created.formatted(date: .omitted, time: .shortened)
        if let source = bud.source { return "from \(source) · \(time)" }
        return time
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .textRole(.caption)
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.line, in: Capsule())
    }
}
#endif
