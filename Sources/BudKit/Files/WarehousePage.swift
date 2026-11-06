#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The Library's Warehouse: templates, each a bud with what is inside it, kept out of the lenses.
/// A template card shows what a copy holds, and Stamp a copy puts one into the place picked in
/// its footer. Keep as template, in any bud's menu, or a drop on Warehouse in the sidebar, adds one.
struct WarehousePage: View {
    @ObservedObject var store: BudStore
    /// The place each template stamps into, by template; Everything until one is picked.
    @State private var into: [UUID: UUID] = [:]

    var body: some View {
        let templates = store.tree.templates()
        MaybeScroll {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LIBRARY")
                        .textRole(.eyebrow)
                        .foregroundStyle(Theme.leaf)
                    Text("Warehouse")
                        .textRole(.title)
                        .foregroundStyle(Theme.text)
                    Text(WarehouseText.count(templates.count))
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                }
                if templates.isEmpty {
                    Text(WarehouseText.empty)
                        .textRole(.body)
                        .foregroundStyle(Theme.text3)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(templates) { template in
                            card(template)
                        }
                    }
                }
            }
            .pageColumn()
        }
    }

    private func card(_ template: Bud) -> some View {
        let items = store.tree.children(of: template.id)
        let target = into[template.id] ?? rootID
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.text)
                    .textRole(.label)
                    .foregroundStyle(Theme.text)
                Text(WarehouseText.caption(
                    buds: store.tree.descendants(of: template.id).count + 1,
                    triggers: store.triggers.filter { $0.template == template.text }.count))
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
            }
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items) { item in
                        Text("– \(item.text)")
                            .textRole(.body)
                            .foregroundStyle(Theme.text2)
                            .lineLimit(1)
                    }
                }
            }
            Divider()
            HStack(spacing: 8) {
                Menu {
                    ForEach(places, id: \.self) { place in
                        Button(store.tree.title(of: place)) { into[template.id] = place }
                    }
                } label: {
                    Text("Stamp into \(store.tree.title(of: target))")
                        .textRole(.caption)
                        .foregroundStyle(Theme.text2)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityIdentifier("stamp-into-\(template.id.uuidString)")
                Spacer()
                Button { store.stamp(template.id, into: target) } label: {
                    BudButtonLabel(title: "Stamp a copy", systemImage: "square.on.square")
                }
                .buttonStyle(.budSecondary)
                .accessibilityIdentifier("stamp-\(template.id.uuidString)")
            }
        }
        .padding(14)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Theme.line))
        .contentShape(Rectangle())
        .onTapGesture { store.openAsFile(template.id) }
        .budMenu(template.id, store: store)
    }

    /// Where a copy can go: Everything, each thread, and the Inbox.
    private var places: [UUID] {
        [rootID] + store.tree.children(of: rootID).filter { !$0.isDone }.map(\.id) + [inboxID]
    }
}
#endif

/// The words of the Warehouse page, kept pure so a test reads them on any platform.
public enum WarehouseText {
    public static let empty = "No templates yet. Choose Keep as template in a bud's menu, or drop a bud on Warehouse, and stamp copies of it from here."

    public static func count(_ templates: Int) -> String {
        templates == 1 ? "1 template" : "\(templates) templates"
    }

    /// `Template · 3 buds · used by 1 trigger`: the template and everything inside it.
    public static func caption(buds: Int, triggers: Int = 0) -> String {
        let used = triggers == 0 ? "" : " · used by \(triggers == 1 ? "1 trigger" : "\(triggers) triggers")"
        return "Template · \(buds == 1 ? "1 bud" : "\(buds) buds")\(used)"
    }
}
