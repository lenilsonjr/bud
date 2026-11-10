#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The file tree as a panel: Places, Lenses and Everything's tree, scrolling by itself and
/// taking the rest of its sidebar.
struct FilesPanel: View {
    @ObservedObject var store: BudStore

    var body: some View {
        PanelView(panel: .files, store: store) {
            Sidebar(store: store)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: store.panels.isCollapsed(.files) ? nil : .infinity, alignment: .top)
    }
}

/// The properties the lenses read, each editable: State, When, Due, Pinned and Tags. A field
/// the bud's source owns says so beside its control.
struct PropertiesPanel: View {
    let id: UUID
    @ObservedObject var store: BudStore

    var body: some View {
        if let bud = store.tree.bud(id) {
            PanelView(panel: .properties, store: store) {
                VStack(alignment: .leading, spacing: 2) {
                    PropertyRow(name: "State", from: owner(bud, .state)) {
                        if bud.isTodo {
                            Segmented(selection: Binding(get: { bud.isDone }, set: { if $0 != bud.isDone { store.tick(id) } }), options: [false, true]) { $0 ? "Done" : "Open" }
                        } else {
                            Button("Make a to-do") { store.update(id, text: bud.text, todo: true) }
                                .buttonStyle(.budGhost)
                        }
                    }
                    PropertyRow(name: "When", from: owner(bud, .when)) { DateField(label: "When", date: bud.when) { store.setWhen(id, $0) } }
                    PropertyRow(name: "Due", from: owner(bud, .due)) { DateField(label: "Due", date: bud.due) { store.setDue(id, $0) } }
                    PropertyRow(name: "Pinned") {
                        Button(bud.pinned ? "Pinned" : "Pin", systemImage: bud.pinned ? "pin.fill" : "pin") { store.setPinned(id, !bud.pinned) }
                            .buttonStyle(.budGhost)
                    }
                    PropertyRow(name: "Tags", top: true) { TagRow(bud: bud, store: store) }
                }
                .padding(.horizontal, 10)
            }
        }
    }

    /// The planted bud's `from` key when its source owns this field.
    private func owner(_ bud: Bud, _ field: SourceRowText.Field) -> String? {
        guard let from = bud.from, SourceRowText.owns(field, from: from) else { return nil }
        return from
    }
}

/// One property: its name in the gutter, its control beside it.
struct PropertyRow<Control: View>: View {
    let name: String
    /// The `from` key of the source that owns this field, which marks it.
    var from: String? = nil
    /// Whether the control may run to more than one line, like the tags.
    var top: Bool = false
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: top ? .top : .center, spacing: 8) {
            Text(name)
                .textRole(.label)
                .foregroundStyle(Theme.text3)
                .frame(width: 64, alignment: .leading)
                .padding(.top, top ? 5 : 0)
            control()
            if let from { FromMark(from: from) }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 28)
    }
}

/// A day in a property row: "No day" and Set while empty; the pistil tag the Today lens uses
/// once set, a click on it opens the calendar, Clear beside it.
struct DateField: View {
    let label: String
    let date: Date?
    let set: (Date?) -> Void
    @State private var picking = false

    var body: some View {
        HStack(spacing: 8) {
            if let date {
                Button { picking.toggle() } label: {
                    DateTag(label: label, date: date)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $picking) {
                    DatePicker("", selection: Binding(get: { date }, set: { set($0) }), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding(12)
                }
                Button("Clear") { set(nil) }
                    .buttonStyle(.budGhost)
            } else {
                Text("No day")
                    .textRole(.label)
                    .foregroundStyle(Theme.text3)
                Button("Set") { set(Calendar.current.startOfDay(for: Date())) }
                    .buttonStyle(.budGhost)
            }
        }
    }
}

/// What is inside the bud, every kind, one row each; a click opens the child, the box ticks a
/// to-do. Closed to-dos hide behind a count until Show, and fold again on Hide. The + in the
/// header opens a line to plant one more at the end.
struct InsidePanel: View {
    let id: UUID
    @ObservedObject var store: BudStore
    @State private var showClosed = false
    @State private var adding = false
    @State private var line = ""
    @FocusState private var lineFocused: Bool
    @Environment(\.compact) private var compact

    var body: some View {
        if let bud = store.tree.bud(id) {
            let kids = store.tree.children(of: id)
            let closed = kids.filter(\.isDone).count
            let shown = showClosed ? kids : kids.filter { !$0.isDone }
            PanelView(panel: .inside, store: store, meta: kids.isEmpty ? nil : "\(kids.count)", onAdd: { open() }) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(shown) { child in
                        PanelRow(
                            title: child.text, meta: PanelRowText.meta(for: child, in: store.tree), done: child.isDone,
                            action: { store.center = child.id }
                        ) {
                            RowMark(bud: child, onTick: { store.tick(child.id) })
                        }
                        .budMenu(child.id, store: store)
                    }
                    if closed > 0 {
                        Button(showClosed ? "Hide closed" : "\(closed) closed hidden · Show") { showClosed.toggle() }
                            .buttonStyle(.plain)
                            .textRole(.caption)
                            .foregroundStyle(Theme.text3)
                            .padding(.leading, 30)
                            .padding(.top, 4)
                    }
                    if kids.isEmpty && !adding {
                        Text("Nothing inside yet.")
                            .textRole(.caption)
                            .foregroundStyle(Theme.text3)
                            .padding(.horizontal, 6)
                    }
                    if adding { addLine(bud) }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func open() {
        if store.isPanelCollapsed(.inside, compact: compact) { store.togglePanel(.inside, compact: compact) }
        adding = true
    }

    /// The line a new child is typed on; ↩ plants it under this bud and keeps the line for the
    /// next, Esc, Cancel or an empty ↩ closes it. Focus is asked for once the field is there,
    /// since asking in the same update that adds it is lost.
    private func addLine(_ bud: Bud) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .foregroundStyle(Theme.text3)
                .frame(width: 16)
            TextField("Add inside \(bud.text)", text: $line)
                .textFieldStyle(.plain)
                .textStyle(PanelText.title)
                .focused($lineFocused)
                .onAppear { lineFocused = true }
                .onSubmit {
                    guard store.add(line, todo: store.tree.suggestsTodo(under: id), under: id) != nil else {
                        adding = false
                        return
                    }
                    line = ""
                }
                .accessibilityIdentifier("inside-add")
                #if os(macOS)
                .onExitCommand { adding = false }
                #endif
            #if os(iOS)
            // No Esc on a touch screen: Cancel closes the line.
            Button("Cancel") { adding = false }
                .buttonStyle(.budGhost)
            #endif
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
    }
}

/// The bud's place: the trail above it, each step openable, the parent's first paragraph
/// quoted, and a way to its page.
struct WhereItLivesPanel: View {
    let id: UUID
    @ObservedObject var store: BudStore

    var body: some View {
        if store.tree.bud(id) != nil {
            let above = Array(store.tree.ancestors(of: id).reversed())
            let parent = above.last ?? rootID
            let lede = store.tree.lede(of: parent)
            PanelView(panel: .whereItLives, store: store) {
                VStack(alignment: .leading, spacing: 8) {
                    trail(above)
                    if !lede.isEmpty {
                        Text(lede)
                            .textRole(.label)
                            .fontWeight(.regular)
                            .lineSpacing(12 * 0.5)
                            .foregroundStyle(Theme.text2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 10)
                            .padding(.vertical, 1)
                            .overlay(alignment: .leading) { Theme.leafLine.frame(width: 2) }
                    }
                    Button { store.center = parent } label: {
                        Text("Open \(store.tree.title(of: parent))  →")
                            .textRole(.label)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.leaf)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("open-parent")
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 2)
            }
        }
    }

    /// Everything › the thread › … each a step that opens.
    private func trail(_ above: [UUID]) -> some View {
        WrapStack(spacing: 4) {
            ForEach(Array(above.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Text("›")
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                }
                Button(store.tree.title(of: step)) { store.center = step }
                    .buttonStyle(.plain)
                    .textRole(.label)
                    .fontWeight(.regular)
                    .foregroundStyle(Theme.text3)
                    .lineLimit(1)
            }
        }
    }
}

/// The buds whose body links to this page, each with where it lives; a click goes to that bud,
/// and the sentence the link sits in is its help. The store keeps the rows between changes of
/// the tree, so a publish while typing does not read every bud again.
struct LinkedFromPanel: View {
    let id: UUID
    @ObservedObject var store: BudStore

    var body: some View {
        if store.tree.bud(id) != nil {
            let links = store.backlinks(to: id)
            PanelView(panel: .linkedFrom, store: store, meta: links.isEmpty ? nil : "\(links.count)") {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(links) { link in
                        PanelRow(
                            title: store.tree.title(of: link.from), meta: store.tree.trail(of: link.from).last ?? "",
                            action: { store.center = link.from }
                        ) {
                            Image(systemName: "arrow.turn.down.right")
                                .textRole(.caption)
                                .foregroundStyle(Theme.text3)
                        }
                        .help(link.sentence)
                    }
                    if links.isEmpty {
                        Text("Nothing links here yet.")
                            .textRole(.caption)
                            .foregroundStyle(Theme.text3)
                            .padding(.horizontal, 6)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

/// Where the bud came from: for a planted bud its source item, the last sync and Open in …;
/// for one written here, its file as the vault holds it, read again after each change.
struct SourcePanel: View {
    let id: UUID
    @ObservedObject var store: BudStore
    @State private var text: String?

    var body: some View {
        if let bud = store.tree.bud(id) {
            PanelView(panel: .source, store: store, meta: bud.from.map(SourceRowText.name) ?? "Written in Bud") {
                Group {
                    if let from = bud.from {
                        SourcePageRow(from: from, mark: store.mark(of: bud))
                    } else {
                        Text(text ?? "Reading the file…")
                            .textRole(.mono)
                            .foregroundStyle(text == nil ? Theme.text3 : Theme.text2)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .task(id: bud) { text = await store.fileText(of: id) }
                    }
                }
                .padding(.horizontal, 10)
            }
        }
    }
}
#endif
