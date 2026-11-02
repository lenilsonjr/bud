#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The left pane of Files: Places, Lenses, and Everything opened into the tree. Only Everything
/// has rows today; the Inbox lists its captures; Archive and Trash wait for the vault.
struct Sidebar: View {
    @ObservedObject var store: BudStore
    @State private var expanded: Set<UUID> = []

    var body: some View {
        ScrollViewReader { proxy in
            MaybeScroll {
                VStack(alignment: .leading, spacing: 2) {
                    eyebrow("Places")
                    place("Inbox", glyph: "tray", count: store.tree.inbox().count, selected: store.inboxOpen) { store.openInbox() }
                    place("Everything", glyph: "leaf.fill", count: nil, selected: !store.inboxOpen && store.lens == nil && store.center == rootID) { store.center = rootID; store.lens = nil; store.inboxOpen = false }
                    ForEach(store.tree.outline(expanded: expanded), id: \.self) { row in
                        if let bud = store.tree.bud(row.id) {
                            TreeRow(
                                bud: bud,
                                tree: store.tree,
                                depth: row.depth,
                                selected: !store.inboxOpen && store.lens == nil && store.center == bud.id,
                                expanded: expanded.contains(bud.id),
                                onSelect: { store.center = bud.id; store.inboxOpen = false },
                                onDisclose: { toggle(bud.id) }
                            )
                            .budMenu(bud.id, store: store)
                            .id(bud.id)
                        }
                    }
                    place("Archive", glyph: "archivebox", count: nil, selected: false, action: nil)
                    place("Trash", glyph: "trash", count: nil, selected: false, action: nil)
                    eyebrow("Lenses").padding(.top, 14)
                    let today = store.tree.today()
                    place("Today", glyph: "sun.max", count: today.due.count + today.scheduled.count, selected: store.lens == .today) { store.lens = .today }
                    place("To-dos", glyph: "checkmark.square", count: nil, selected: store.lens == .todos) { store.lens = .todos }
                    place("Pinned", glyph: "pin", count: nil, selected: store.lens == .pinned) { store.lens = .pinned }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            .onAppear { reveal(store.center, proxy: proxy) }
            .onChange(of: store.center) { _, now in reveal(now, proxy: proxy) }
        }
    }

    /// Opens every ancestor of the selection so its row is on screen, opens the selection one
    /// level when it has children, then scrolls to it.
    private func reveal(_ id: UUID, proxy: ScrollViewProxy) {
        expanded.formUnion(store.tree.ancestors(of: id))
        if store.tree.hasChildren(id) { expanded.insert(id) }
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
    }

    private func toggle(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.15)) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .textRole(.eyebrow)
            .foregroundStyle(Theme.text3)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
    }

    private func place(_ name: String, glyph: String, count: Int?, selected: Bool, action: (() -> Void)?) -> some View {
        Button(action: action ?? {}) {
            HStack(spacing: 8) {
                Image(systemName: glyph)
                    .frame(width: 16)
                    .foregroundStyle(selected ? Theme.leaf : Theme.text2)
                Text(name)
                    .textRole(.body)
                    .foregroundStyle(action == nil ? Theme.text3 : Theme.text)
                Spacer()
                if let count, count > 0 {
                    Text("\(count)")
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(selected ? Theme.leafSoft : .clear, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}
#endif
