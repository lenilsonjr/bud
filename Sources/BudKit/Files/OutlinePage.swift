#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// A folder's page (C1): the page header, the lede, and the outline of what is inside, one
/// level open, each row opening one more level in place. Everything's page is the same with
/// the threads as rows. A leaf has the document view instead.
struct OutlinePage: View {
    @ObservedObject var store: BudStore
    @State private var expanded: Set<UUID>
    @State private var showClosed = false
    @State private var enrich = ""
    @State private var moving: Bud? = nil
    @Environment(\.compact) private var compact

    private static let title = TextStyle(typeface: .display, size: 32, weight: 500)

    init(store: BudStore, expanded: Set<UUID> = []) {
        self.store = store
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        let id = store.center
        let rows = store.tree.outline(under: id, expanded: expanded)
        let shown = showClosed ? rows : rows.filter { store.tree.bud($0.id)?.isDone != true }
        let hidden = rows.count - shown.count
        MaybeScroll {
            VStack(alignment: .leading, spacing: 18) {
                header(id, hidden: hidden)
                if rows.isEmpty {
                    Text("Nothing written yet.")
                        .textRole(.body)
                        .foregroundStyle(Theme.text3)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(shown, id: \.self) { row in
                            if let bud = store.tree.bud(row.id) {
                                OutlineRow(
                                    bud: bud,
                                    store: store,
                                    depth: row.depth,
                                    expanded: expanded.contains(bud.id),
                                    onDisclose: { toggle(bud.id) },
                                    onMove: { moving = bud }
                                )
                            }
                        }
                    }
                }
                enrichLine(id)
            }
            .pageColumn()
        }
        .sheet(item: $moving) { bud in MoveToPicker(store: store, bud: bud) }
    }

    /// The eyebrow, the title with Show closed and Enrich at its right, and the lede.
    private func header(_ id: UUID, hidden: Int) -> some View {
        let lede = store.tree.lede(of: id)
        return VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow(id))
                .textRole(.eyebrow)
                .foregroundStyle(Theme.leaf)
            if compact {
                Text(id == rootID ? "Everything" : store.tree.title(of: id))
                    .textStyle(Self.title)
                    .foregroundStyle(Theme.text)
                HStack(spacing: 10) {
                    headerButtons(id)
                    Spacer(minLength: 0)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(id == rootID ? "Everything" : store.tree.title(of: id))
                        .textStyle(Self.title)
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 12)
                    headerButtons(id)
                }
            }
            if hidden > 0 {
                Text("\(hidden) closed hidden")
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
            }
            if !lede.isEmpty {
                Text(lede)
                    .textRole(.body)
                    .lineSpacing(14 * 0.55)
                    .foregroundStyle(Theme.text2)
            }
        }
    }

    /// Show closed and Enrich (Capture at Everything), beside the title or under it on a phone.
    @ViewBuilder private func headerButtons(_ id: UUID) -> some View {
        Button { showClosed.toggle() } label: { BudButtonLabel(title: "Show closed") }
            .buttonStyle(showClosed ? .budGhost : .budSecondary)
        Button { store.modal = .adding(under: id) } label: {
            BudButtonLabel(title: id == rootID ? "Capture" : "Enrich", systemImage: "plus")
        }
        .buttonStyle(.budPrimary)
    }

    /// PLACE for Everything, PLACE · THREAD for a first-level bud, BUD below that.
    private func eyebrow(_ id: UUID) -> String {
        if id == rootID { return "Place" }
        return store.tree.parent(of: id) == rootID ? "Place · Thread" : "Bud"
    }

    private func enrichLine(_ id: UUID) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .foregroundStyle(Theme.text3)
            TextField(id == rootID ? "Capture a line…" : "Enrich \(store.tree.title(of: id))…", text: $enrich)
                .textFieldStyle(.plain)
                .onSubmit {
                    if id == rootID { store.capture(enrich) } else { store.add(enrich, todo: store.tree.suggestsTodo(under: id), under: id) }
                    enrich = ""
                }
        }
        .textRole(.body)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }

    private func toggle(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.15)) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }
}
#endif
