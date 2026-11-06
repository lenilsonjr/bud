#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The Files view: the sidebar with Places, Lenses and the tree, and the page of the selected
/// bud. The selection is the store's center, so Canvas and Files always agree on where you are.
/// Drawn as two panes rather than a split view so it looks the same everywhere and in pictures.
struct FilesView: View {
    @ObservedObject var store: BudStore
    @Environment(\.compact) private var compact

    static let sidebarWidth: CGFloat = 264

    var body: some View {
        if compact {
            PhoneFilesView(store: store)
        } else {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    if sidebarShown(in: geo.size) {
                        Sidebar(store: store)
                            .frame(width: Self.sidebarWidth)
                            .background(Theme.sidebar)
                        Rectangle()
                            .fill(Theme.line)
                            .frame(width: 1)
                    }
                    FilesPage(store: store)
                }
                .animation(.easeOut(duration: 0.2), value: sidebarShown(in: geo.size))
                .onAppear { sync(geo.size) }
                .onChange(of: geo.size) { _, now in sync(now) }
            }
        }
    }

    /// The Mac always shows the sidebar; only iOS collapses it, and only iOS has the button.
    private func sidebarShown(in size: CGSize) -> Bool {
        #if os(iOS)
        store.sidebar.isShown(in: size)
        #else
        true
        #endif
    }

    private func sync(_ size: CGSize) {
        store.surfaceSize = size
        store.sidebar.resized(to: size)
    }
}

/// The page for where you are: a lens, a place, a folder's outline or a leaf's document.
struct FilesPage: View {
    @ObservedObject var store: BudStore

    var body: some View {
        Group {
            if let lens = store.lens {
                LensPage(store: store, lens: lens)
            } else if let place = store.place {
                switch place {
                case .inbox: InboxPage(store: store)
                case .archive: ArchivePage(store: store)
                case .trash: TrashPage(store: store)
                case .warehouse: WarehousePage(store: store)
                case .triggers: TriggersPage(store: store)
                }
            } else if store.center == rootID || store.tree.hasChildren(store.center) {
                OutlinePage(store: store)
            } else {
                // A page of its own for each bud, so a link followed in read mode opens the next
                // page reading, not in the editor the last one left open.
                DocumentView(id: store.center, store: store)
                    .id(store.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }
}
#endif
