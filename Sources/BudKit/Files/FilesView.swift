#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The Files view: the page between two sidebars of panels, the file tree on the left and the
/// page's own panels on the right. The selection is the store's center, so Canvas and Files
/// always agree on where you are. Drawn as panes rather than a split view so it looks the same
/// everywhere and in pictures.
struct FilesView: View {
    @ObservedObject var store: BudStore
    @Environment(\.compact) private var compact

    var body: some View {
        if compact {
            PhoneFilesView(store: store)
        } else {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    if sidebarShown(.left, in: geo.size) {
                        PanelSidebar(store: store, side: .left)
                        Rectangle()
                            .fill(Theme.line)
                            .frame(width: 1)
                    }
                    FilesPage(store: store)
                    if sidebarShown(.right, in: geo.size) {
                        Rectangle()
                            .fill(Theme.line)
                            .frame(width: 1)
                        PanelSidebar(store: store, side: .right)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: sidebarShown(.left, in: geo.size))
                .animation(.easeOut(duration: 0.2), value: sidebarShown(.right, in: geo.size))
                .onAppear { sync(geo.size) }
                .onChange(of: geo.size) { _, now in sync(now) }
            }
        }
    }

    /// A sidebar shows unless the page bar hid it. The right one is the page's own panels, so
    /// it goes with a bud's page alone: a lens, a place and Everything have none. The Mac always
    /// has room; iOS folds both away in a narrow window, and the bar button brings them back.
    private func sidebarShown(_ side: PanelSide, in size: CGSize) -> Bool {
        guard store.panels.shows(side) else { return false }
        if side == .right && !showsBudPage { return false }
        #if os(iOS)
        return store.sidebar.isShown(in: size)
        #else
        return true
        #endif
    }

    private var showsBudPage: Bool {
        store.lens == nil && store.place == nil && store.tree.bud(store.center) != nil
    }

    private func sync(_ size: CGSize) {
        store.surfaceSize = size
        store.sidebar.resized(to: size)
    }
}

/// The page for where you are: a lens, a place, or the bud's page, the same one for every bud.
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
            } else if store.center == rootID {
                EverythingPage(store: store)
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

/// Everything's page: the root is no bud and has no body, so its title and a line pointing at
/// the threads, which the tree beside it lists.
struct EverythingPage: View {
    @ObservedObject var store: BudStore

    var body: some View {
        MaybeScroll {
            VStack(alignment: .leading, spacing: 10) {
                Text(store.tree.title(of: rootID))
                    .textRole(.title)
                    .foregroundStyle(Theme.text)
                Text("Pick a thread to read it.")
                    .textRole(.body)
                    .foregroundStyle(Theme.text3)
            }
            .pageColumn()
        }
    }
}
#endif
