#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// A lens holds nothing: it is a query across every thread. Today shows what is due and what is
/// scheduled; To-dos every open to-do by thread; Pinned the pinned buds.
struct LensPage: View {
    @ObservedObject var store: BudStore
    let lens: Lens

    var body: some View {
        LensColumn(eyebrow: "LENS · ACROSS ALL THREADS", title: lens.rawValue) {
            switch lens {
            case .today:
                let today = store.tree.today(on: store.now)
                LensGroup(store: store, name: "Due", buds: today.due, tag: { bud in bud.due.map { ("Due", $0) } })
                LensGroup(store: store, name: "Scheduled for today", buds: today.scheduled, tag: { bud in bud.when.map { ("When", $0) } })
                if today.due.isEmpty && today.scheduled.isEmpty { LensNothing(text: "Nothing due or scheduled. A clear day.") }
            case .todos:
                let threads = store.tree.openTodos()
                ForEach(threads, id: \.thread.id) { entry in
                    LensGroup(store: store, name: entry.thread.text, buds: entry.todos, tag: { bud in bud.due.map { ("Due", $0) } })
                }
                if threads.isEmpty { LensNothing(text: "No open to-dos anywhere.") }
            case .pinned:
                let pinned = store.tree.pinned()
                LensGroup(store: store, name: "Pinned", buds: pinned, tag: { _ in nil })
                if pinned.isEmpty { LensNothing(text: "Nothing pinned yet.") }
            }
        }
    }
}

/// A saved lens's page: what its question finds across every thread, grouped by thread, with
/// any due date beside each hit.
struct SavedLensPage: View {
    @ObservedObject var store: BudStore
    let lens: SavedLens

    var body: some View {
        LensColumn(eyebrow: "SAVED LENS · ACROSS ALL THREADS", title: lens.name) {
            let groups = lens.query.hitsByThread(store.tree, links: store.links, on: store.now)
            ForEach(groups, id: \.thread.id) { group in
                LensGroup(store: store, name: group.thread.text, buds: group.hits, tag: { bud in bud.due.map { ("Due", $0) } })
            }
            if groups.isEmpty { LensNothing(text: "Nothing matches this lens right now.") }
        }
    }
}

/// The page every lens shares: the eyebrow and the title above, then what the lens finds.
struct LensColumn<Content: View>: View {
    let eyebrow: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        MaybeScroll {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow)
                        .textRole(.eyebrow)
                        .foregroundStyle(Theme.text3)
                    Text(title)
                        .textRole(.title)
                        .foregroundStyle(Theme.text)
                }
                content
            }
            .pageColumn()
        }
    }
}

/// One group of a lens page under its name; nothing at all when it holds no buds.
struct LensGroup: View {
    @ObservedObject var store: BudStore
    let name: String
    let buds: [Bud]
    let tag: (Bud) -> (String, Date)?

    var body: some View {
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
}

/// What a lens page says when it finds nothing.
struct LensNothing: View {
    let text: String

    var body: some View {
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
        VStack(alignment: .leading, spacing: 2) {
            let crumbs = store.tree.breadcrumb(of: bud.id)
            if !crumbs.isEmpty {
                Text(crumbs.joined(separator: " › "))
                    .textRole(.caption)
                    .lineLimit(1)
                    .foregroundStyle(Theme.text3)
                    .padding(.leading, 24)
            }
            HStack(alignment: .top, spacing: 8) {
                RowMark(bud: bud, onTick: { store.tick(bud.id) })
                Text(bud.text)
                    .textRole(.body)
                    .strikethrough(bud.isDone)
                    .foregroundStyle(bud.isDone ? Theme.text3 : Theme.text)
                Spacer()
                if let tag {
                    DateTag(label: tag.0, date: tag.1)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .rowHairline()
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
