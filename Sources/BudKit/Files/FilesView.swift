#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The Files view: the sidebar with Places, Lenses and the tree, and the page of the selected
/// bud. The selection is the store's center, so Canvas and Files always agree on where you are.
/// Drawn as two panes rather than a split view so it looks the same everywhere and in pictures.
struct FilesView: View {
    @ObservedObject var store: BudStore

    static let sidebarWidth: CGFloat = 240

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(store: store)
                .frame(width: Self.sidebarWidth)
                .background(Theme.sidebar)
            Rectangle()
                .fill(Theme.line)
                .frame(width: 1)
            Group {
                if let lens = store.lens {
                    LensPage(store: store, lens: lens)
                } else if store.inboxOpen {
                    InboxPage(store: store)
                } else {
                    OutlinePage(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
        }
    }
}

/// A folder's page for now: the title, what it is, and its children as rows. A leaf shows the
/// place its document will take. The editor and the outline proper are the next tickets.
struct OutlinePage: View {
    @ObservedObject var store: BudStore

    var body: some View {
        let id = store.center
        let kids = store.tree.children(of: id)
        MaybeScroll {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.tree.title(of: id))
                        .textRole(.title)
                        .foregroundStyle(Theme.text)
                    if let bud = store.tree.bud(id) {
                        Text(CardStyle.caption(for: bud, in: store.tree))
                            .textRole(.caption)
                            .foregroundStyle(Theme.text3)
                    } else {
                        Text("\(kids.count) threads")
                            .textRole(.caption)
                            .foregroundStyle(Theme.text3)
                    }
                }
                if kids.isEmpty {
                    Text("Nothing written yet.")
                        .textRole(.body)
                        .foregroundStyle(Theme.text3)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(kids) { bud in
                            Button { store.center = bud.id } label: {
                                PageRow(bud: bud, tree: store.tree)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }
}

private struct PageRow: View {
    let bud: Bud
    let tree: Tree

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            KindMark(bud: bud, style: CardStyle.chip(for: bud, lit: false))
            Text(bud.text)
                .strikethrough(bud.isDone)
                .foregroundStyle(bud.isDone ? Theme.text3 : Theme.text)
            Spacer()
            Text(CardStyle.caption(for: bud, in: tree))
                .textRole(.caption)
                .foregroundStyle(Theme.text3)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}
#endif
