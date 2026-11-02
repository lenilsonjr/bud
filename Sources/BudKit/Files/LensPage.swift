#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// A lens holds nothing: it is a query across every thread. Today shows what is due and what is
/// scheduled; To-dos every open to-do by thread; Pinned the pinned buds.
struct LensPage: View {
    @ObservedObject var store: BudStore
    let lens: Lens

    var body: some View {
        MaybeScroll {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LENS · ACROSS ALL THREADS")
                        .textRole(.eyebrow)
                        .foregroundStyle(Theme.text3)
                    Text(lens.rawValue)
                        .textRole(.title)
                        .foregroundStyle(Theme.text)
                }
                switch lens {
                case .today:
                    let today = store.tree.today()
                    group("Due", today.due, tag: { bud in bud.due.map { ("Due", $0) } })
                    group("Scheduled for today", today.scheduled, tag: { bud in bud.when.map { ("When", $0) } })
                    if today.due.isEmpty && today.scheduled.isEmpty { nothing("Nothing due or scheduled. A clear day.") }
                case .todos:
                    let threads = store.tree.openTodos()
                    ForEach(threads, id: \.thread.id) { entry in
                        group(entry.thread.text, entry.todos, tag: { bud in bud.due.map { ("Due", $0) } })
                    }
                    if threads.isEmpty { nothing("No open to-dos anywhere.") }
                case .pinned:
                    let pinned = store.tree.pinned()
                    group("Pinned", pinned, tag: { _ in nil })
                    if pinned.isEmpty { nothing("Nothing pinned yet.") }
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    @ViewBuilder
    private func group(_ name: String, _ buds: [Bud], tag: @escaping (Bud) -> (String, Date)?) -> some View {
        if !buds.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(name.uppercased())
                    .textRole(.eyebrow)
                    .foregroundStyle(Theme.text3)
                    .padding(.bottom, 4)
                ForEach(buds) { bud in
                    ListRow(bud: bud, store: store, tag: tag(bud))
                }
            }
        }
    }

    private func nothing(_ text: String) -> some View {
        Text(text)
            .textRole(.body)
            .foregroundStyle(Theme.text3)
    }
}

/// One row of a lens: the breadcrumb above the title, the box or dot, a date tag in pistil.
/// A click selects the bud in Files; ⌘-click centers it on the canvas.
struct ListRow: View {
    let bud: Bud
    @ObservedObject var store: BudStore
    let tag: (String, Date)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
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
                let crumbs = store.tree.breadcrumb(of: bud.id)
                if !crumbs.isEmpty {
                    Text(crumbs.joined(separator: " › "))
                        .textRole(.caption)
                        .lineLimit(1)
                        .foregroundStyle(Theme.text3)
                }
                Text(bud.text)
                    .textRole(.body)
                    .strikethrough(bud.isDone)
                    .foregroundStyle(bud.isDone ? Theme.text3 : Theme.text)
            }
            Spacer()
            if let tag {
                Text("\(tag.0) \(tag.1.formatted(date: .abbreviated, time: .omitted))")
                    .textRole(.label)
                    .foregroundStyle(Theme.pistil)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.pistilSoft, in: Capsule())
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture { store.openAsFile(bud.id) }
        .modifier(CommandClick { store.center = bud.id; store.surface = .canvas })
        .budMenu(bud.id, store: store)
    }
}

/// ⌘-click on macOS; a plain tap elsewhere does the ordinary thing.
private struct CommandClick: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content.simultaneousGesture(TapGesture().modifiers(.command).onEnded(action))
        #else
        content
        #endif
    }
}
#endif
