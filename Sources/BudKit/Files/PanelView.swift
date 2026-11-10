#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// One panel of a sidebar: the header with its grip, title, a count or a word beside it, an
/// optional +, the ⋯ menu and the chevron that folds the body away; the body below while open;
/// a hairline under. Dragging the header lifts the panel: its place fades, and the leaf drop
/// line shows on the panel it would land above, or under the last one.
struct PanelView<Content: View>: View {
    let panel: PagePanel
    @ObservedObject var store: BudStore
    /// Beside the title: a count, or a word like "Written in Bud".
    var meta: String? = nil
    var onAdd: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content
    @Environment(\.panelDragging) private var dragging
    @Environment(\.stillPicture) private var still
    @State private var menuOpen = false

    static var headerHeight: CGFloat { 32 }

    var body: some View {
        let collapsed = store.panels.isCollapsed(panel)
        let line = dragging.drag?.drop?.line(on: panel, in: store.panels.layout)
        VStack(alignment: .leading, spacing: 0) {
            header(collapsed: collapsed)
            if !collapsed {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
        .opacity(dragging.drag?.panel == panel ? 0.3 : 1)
        .overlay(alignment: .top) { if line == .above { PanelDropLine().offset(y: -4) } }
        .overlay(alignment: .bottom) { if line == .below { PanelDropLine().offset(y: 4) } }
        .background(probe)
        .accessibilityIdentifier("panel-\(panel.rawValue)")
    }

    /// Tells Files where this panel is while one is in hand, so the drop line can find its gap.
    private var probe: some View {
        GeometryReader { geo in
            Color.clear.onChange(of: dragging.drag?.point) { _, now in
                guard now != nil else { return }
                dragging.placed(panel, geo.frame(in: .named(FilesView.space)))
            }
        }
    }

    private func header(collapsed: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .textRole(.caption)
                .foregroundStyle(Theme.text3.opacity(0.5))
                .accessibilityHidden(true)
            Text(panel.title)
                .textRole(.eyebrow)
                .foregroundStyle(Theme.text3)
            if let meta, !meta.isEmpty {
                Text(meta)
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .textRole(.label)
                        .foregroundStyle(Theme.leaf)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add inside")
                .accessibilityLabel("Add inside \(panel.title)")
            }
            menuButton
            Button {
                withAnimation(.easeOut(duration: 0.15)) { store.panels.toggle(panel) }
            } label: {
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(collapsed ? "Show \(panel.title)" : "Collapse \(panel.title)")
            .accessibilityLabel(collapsed ? "Show \(panel.title)" : "Collapse \(panel.title)")
            .accessibilityIdentifier("panel-\(panel.rawValue)-chevron")
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: Self.headerHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .named(FilesView.space))
                .onChanged { dragging.moved(panel, $0.location) }
                .onEnded { dragging.ended(panel, $0.location) }
        )
    }

    /// The ⋯ that opens the panel's menu. The picture renderer cannot draw a popover, so a still
    /// picture shows the button alone.
    private var menuButton: some View {
        Button { menuOpen.toggle() } label: {
            Image(systemName: "ellipsis")
                .textRole(.caption)
                .foregroundStyle(Theme.text3)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(panel.title) panel menu")
        .accessibilityLabel("\(panel.title) panel menu")
        .accessibilityIdentifier("panel-\(panel.rawValue)-menu")
        .popover(isPresented: still ? .constant(false) : $menuOpen, arrowEdge: .bottom) {
            PanelMenu(panel: panel, store: store) { menuOpen = false }
            #if os(iOS)
            .presentationCompactAdaptation(.popover)
            #endif
        }
    }
}

/// The leaf line a dragged panel lands on: a dot at its start and a line across the sidebar.
struct PanelDropLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle().fill(Theme.leaf).frame(width: 8, height: 8)
            Capsule().fill(Theme.leaf).frame(height: 2)
        }
        .frame(height: 8)
        .padding(.horizontal, 10)
        .accessibilityHidden(true)
    }
}

/// The ⋯ menu of a panel, its items as `PanelMenuItem` lists them, in three groups. Each runs
/// through the store, so a move reaches every device.
struct PanelMenu: View {
    let panel: PagePanel
    @ObservedObject var store: BudStore
    var onChoose: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(PanelMenuItem.allCases, id: \.self) { item in
                if item.startsGroup { Divider().padding(.vertical, 3) }
                row(item)
            }
        }
        .padding(5)
        .frame(width: 220, alignment: .leading)
        .accessibilityIdentifier("panel-menu")
    }

    private func row(_ item: PanelMenuItem) -> some View {
        let enabled = item.isEnabled(for: panel, in: store.panels)
        return Button {
            store.arrange { item.apply(to: &$0, for: panel) }
            onChoose()
        } label: {
            HStack(spacing: 8) {
                Text(item.title(for: panel, in: store.panels))
                    .textRole(.body)
                    .foregroundStyle(enabled ? Theme.text : Theme.text3)
                Spacer(minLength: 8)
                if item == .showHidden, !store.panels.layout.hidden.isEmpty {
                    Text("\(store.panels.layout.hidden.count)")
                        .textRole(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.text3)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// What a panel needs from Files while one is in hand: the drag itself, and the way to say
/// where it is, where the pointer went and where it let go. Files sets it; a still picture sets
/// the drag alone, to show the line.
struct PanelDragging {
    var drag: PanelDrag? = nil
    var placed: (PagePanel, CGRect) -> Void = { _, _ in }
    var moved: (PagePanel, CGPoint) -> Void = { _, _ in }
    var ended: (PagePanel, CGPoint) -> Void = { _, _ in }
}

private struct PanelDraggingKey: EnvironmentKey {
    static let defaultValue = PanelDragging()
}

/// The panel a still picture shows in hand, since a picture has no pointer to drag one.
struct StillPanelDragKey: EnvironmentKey {
    static let defaultValue: PanelDrag? = nil
}

extension EnvironmentValues {
    var panelDragging: PanelDragging {
        get { self[PanelDraggingKey.self] }
        set { self[PanelDraggingKey.self] = newValue }
    }

    var stillPanelDrag: PanelDrag? {
        get { self[StillPanelDragKey.self] }
        set { self[StillPanelDragKey.self] = newValue }
    }
}

/// The one-off style of a panel row's title: a step under the body text.
enum PanelText {
    static let title = TextStyle(typeface: .text, size: 13, weight: 400)
}

/// One row in a panel: the lead mark, the title, and the meta on the right. A click runs the
/// action, when there is one.
struct PanelRow<Lead: View>: View {
    let title: String
    var meta: String = ""
    var done: Bool = false
    var action: (() -> Void)? = nil
    @ViewBuilder let lead: () -> Lead

    var body: some View {
        let line = HStack(spacing: 8) {
            lead().frame(width: 16, height: 16)
            Text(title)
                .textStyle(PanelText.title)
                .lineLimit(1)
                .strikethrough(done)
                .foregroundStyle(done ? Theme.text3 : Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !meta.isEmpty {
                Text(meta)
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
        .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        if let action {
            Button(action: action) { line }
                .buttonStyle(.plain)
        } else {
            line
        }
    }
}

/// A column of panels: the left or the right sidebar. A column with the file tree in it lets the
/// tree scroll by itself and fill the height; any other column scrolls as one.
struct PanelSidebar: View {
    @ObservedObject var store: BudStore
    let side: PanelSide

    static let leftWidth: CGFloat = 272
    static let rightWidth: CGFloat = 300

    var body: some View {
        let panels = Self.panels(on: side, store: store)
        Group {
            if panels.contains(.files) {
                column(panels)
            } else {
                MaybeScroll { column(panels) }
            }
        }
        .frame(width: side == .left ? Self.leftWidth : Self.rightWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.window)
        .accessibilityIdentifier("sidebar-\(side.rawValue)")
    }

    /// The panels a side shows here: the page's own go with a bud's page alone, so a lens, a
    /// place and Everything show the file tree only.
    static func panels(on side: PanelSide, store: BudStore) -> [PagePanel] {
        let panels = store.panels.layout.panels(on: side)
        return FilesPage.showsBudPage(store) ? panels : panels.filter { $0 == .files }
    }

    private func column(_ panels: [PagePanel]) -> some View {
        VStack(spacing: 0) {
            ForEach(panels, id: \.self) { panel in
                Self.panel(panel, store: store)
            }
        }
    }

    /// The view of a panel, for its column and for the lifted copy while it is dragged.
    @ViewBuilder static func panel(_ panel: PagePanel, store: BudStore) -> some View {
        switch panel {
        case .files:
            FilesPanel(store: store)
        case .properties:
            PropertiesPanel(id: store.center, store: store)
        case .inside:
            InsidePanel(id: store.center, store: store)
        case .whereItLives:
            WhereItLivesPanel(id: store.center, store: store)
        case .linkedFrom:
            LinkedFromPanel(id: store.center, store: store)
        case .source:
            SourcePanel(id: store.center, store: store)
        }
    }
}
#endif
