#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The Files view: the sidebar with Places, Lenses and the tree, and the page of the selected
/// bud. The selection is the store's center, so Canvas and Files always agree on where you are.
/// Drawn as two panes rather than a split view so it looks the same everywhere and in pictures.
struct FilesView: View {
    @ObservedObject var store: BudStore

    static let sidebarWidth: CGFloat = 264

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
                } else if let place = store.place {
                    switch place {
                    case .inbox: InboxPage(store: store)
                    case .archive: ArchivePage(store: store)
                    case .trash: TrashPage(store: store)
                    }
                } else if store.center == rootID || store.tree.hasChildren(store.center) {
                    OutlinePage(store: store)
                } else {
                    DocumentView(id: store.center, store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
        }
    }
}
#endif
