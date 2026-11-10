#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The Files view: the page between two sidebars of panels, the file tree on the left and the
/// page's own panels on the right. The selection is the store's center, so Canvas and Files
/// always agree on where you are. Drawn as panes rather than a split view so it looks the same
/// everywhere and in pictures. A panel dragged by its header is drawn here, lifted under the
/// pointer, and lands in the gap the drop line showed, in either sidebar.
struct FilesView: View {
    @ObservedObject var store: BudStore
    @Environment(\.compact) private var compact
    /// Files holds the keyboard itself when no field in it does, so its keys reach it.
    @FocusState private var focused: Bool
    @Environment(\.stillPanelDrag) private var stillDrag
    /// The panel in hand and where the pointer is, in this view's space.
    @State private var inHand: (panel: PagePanel, at: CGPoint)? = nil
    /// Where each panel is, in this view's space, as the panels report it during a drag.
    @State private var frames: [PagePanel: CGRect] = [:]

    static let space = "files"

    var body: some View {
        if compact {
            PhoneFilesView(store: store)
        } else {
            GeometryReader { geo in
                let moving = drag(in: geo.size) ?? stillDrag
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
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onKey(.newUnderThis) { _ in
                    // N under the page, as under the lit card: a line being typed keeps its letter.
                    guard !Keys.typing else { return .ignored }
                    return store.perform(.newUnderThis) ? .handled : .ignored
                }
                .coordinateSpace(name: Self.space)
                .environment(\.panelDragging, PanelDragging(
                    drag: moving,
                    placed: { frames[$0] = $1 },
                    moved: { panel, point in inHand = (panel, point) },
                    ended: { panel, point in
                        if let target = drop(at: point, in: geo.size) {
                            let index = target.index(moving: panel, in: store.panels.layout)
                            store.arrange { $0.layout.move(panel, to: target.side, at: index) }
                        }
                        inHand = nil
                        frames = [:]
                    }
                ))
                .overlay(alignment: .topLeading) {
                    if let moving { lifted(moving).offset(x: moving.point.x - 8, y: moving.point.y - 8) }
                }
                .onAppear {
                    focused = true
                    sync(geo.size)
                }
                .onChange(of: geo.size) { _, now in sync(now) }
            }
        }
    }

    /// The drag with the gap it would land in; nil while nothing is in hand.
    private func drag(in size: CGSize) -> PanelDrag? {
        guard let inHand else { return nil }
        return PanelDrag(panel: inHand.panel, point: inHand.at, drop: drop(at: inHand.at, in: size))
    }

    /// The gap under a point: the sidebar from its x, the gap from the panels' frames. Nil over
    /// the page.
    private func drop(at point: CGPoint, in size: CGSize) -> PanelDrop? {
        let left = sidebarShown(.left, in: size) ? PanelSidebar.leftWidth + 1 : nil
        let right = sidebarShown(.right, in: size) ? PanelSidebar.rightWidth + 1 : nil
        return PanelDrop.side(at: point.x, in: size.width, left: left, right: right).map {
            PanelDrop.under(point, on: $0, frames: frames, layout: store.panels.layout)
        }
    }

    /// The panel in hand, lifted under the pointer: a raised card with the leaf line around it,
    /// a little tilted, the panel's own header and the top of its body.
    private func lifted(_ drag: PanelDrag) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        return PanelSidebar.panel(drag.panel, store: store)
            .environment(\.panelDragging, PanelDragging())
            .frame(width: 290)
            .frame(maxHeight: 180, alignment: .top)
            .clipShape(shape)
            .background(Theme.raised, in: shape)
            .overlay(shape.strokeBorder(Theme.leafLine))
            .shadow(color: Theme.shadowStrong.opacity(0.5), radius: 20, y: 18)
            .rotationEffect(.degrees(-2), anchor: .topLeading)
            .opacity(0.97)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// A sidebar shows unless a toggle hid it, the window is too narrow on iOS, or it has no
    /// panel to show here; one with nothing in it still opens while a panel is in hand, to take
    /// it.
    private func sidebarShown(_ side: PanelSide, in size: CGSize) -> Bool {
        if PanelSidebar.panels(on: side, store: store).isEmpty && inHand == nil { return false }
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

    var body: some View {
        VStack(spacing: 0) {
            if !compact && store.page == nil {
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
