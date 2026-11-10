#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// One panel of a sidebar: the header with its title, a count or a word beside it, an optional
/// + and the chevron that folds the body away; the body below while open; a hairline under.
struct PanelView<Content: View>: View {
    let panel: PagePanel
    @ObservedObject var store: BudStore
    /// Beside the title: a count, or a word like "Written in Bud".
    var meta: String? = nil
    var onAdd: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    static var headerHeight: CGFloat { 32 }

    var body: some View {
        let collapsed = store.panels.isCollapsed(panel)
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
        .accessibilityIdentifier("panel-\(panel.rawValue)")
    }

    private func header(collapsed: Bool) -> some View {
        HStack(spacing: 6) {
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
        let panels = store.panels.layout.panels(on: side)
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

    private func column(_ panels: [PagePanel]) -> some View {
        VStack(spacing: 0) {
            ForEach(panels, id: \.self) { panel in
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
    }
}
#endif
