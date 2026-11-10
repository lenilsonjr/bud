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

    /// A sidebar shows unless a toggle hid it, or the window is too narrow on iOS. The right one
    /// is the page's own panels, so it goes with a bud's page alone: a lens, a place and
    /// Everything have none.
    private func sidebarShown(_ side: PanelSide, in size: CGSize) -> Bool {
        if side == .right && !FilesPage.showsBudPage(store) { return false }
        return store.sidebar.isShown(side, in: size)
    }

    private func sync(_ size: CGSize) {
        store.surfaceSize = size
        store.sidebar.resized(to: size)
    }
}

/// The page for where you are: a lens, a place, or the bud's page, the same one for every bud.
/// A bud's page has its own bar; the others get the sidebar toggle above them.
struct FilesPage: View {
    @ObservedObject var store: BudStore
    @Environment(\.compact) private var compact

    /// Whether the center's page is a bud's: a lens, a place and Everything are not.
    static func showsBudPage(_ store: BudStore) -> Bool {
        store.lens == nil && store.place == nil && store.tree.bud(store.center) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if !compact && !Self.showsBudPage(store) {
                HStack {
                    SidebarToggle(store: store, side: .left)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
            page
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }

    @ViewBuilder private var page: some View {
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
    }
}

/// Hides a sidebar or brings it back; the same switch as the bar button on iOS. The sidebars
/// stay put while editing.
struct SidebarToggle: View {
    @ObservedObject var store: BudStore
    let side: PanelSide

    var body: some View {
        let shown = store.sidebar.isShown(side, in: store.surfaceSize)
        Button {
            withAnimation(.easeOut(duration: 0.2)) { store.sidebar.toggle(side, in: store.surfaceSize) }
        } label: {
            Image(systemName: side == .left ? "sidebar.left" : "sidebar.right")
                .foregroundStyle(shown ? Theme.text2 : Theme.text3)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(shown ? "Hide the \(side.rawValue) sidebar" : "Show the \(side.rawValue) sidebar")
        .accessibilityLabel(shown ? "Hide the \(side.rawValue) sidebar" : "Show the \(side.rawValue) sidebar")
        .accessibilityIdentifier("sidebar-\(side.rawValue)-toggle")
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
