#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI
#if os(iOS)
import GameController
#endif

/// A bud as its own file: the doc bar with its path, the properties the lenses read, the body,
/// and what is inside it. The body autosaves half a second after the last keystroke.
struct DocumentView: View {
    let id: UUID
    @ObservedObject var store: BudStore
    @State private var draft = ""
    @State private var editing = false
    @State private var dirty = false
    @State private var saver: Task<Void, Never>?
    @State private var enrich = ""
    /// The `[[` picker's highlighted row, and the open `[[` it was closed on with Esc.
    @State private var pick = 0
    @State private var closedAt: Int?
    /// Whether the last edit was typed at the open `[[`, so ↩, ⇥ and the arrows are the picker's.
    @State private var armed = false
    @FocusState private var bodyFocused: Bool

    var body: some View {
        if let bud = store.tree.bud(id) {
            MaybeScroll {
                VStack(alignment: .leading, spacing: 20) {
                    docBar(bud)
                    Text(bud.text)
                        .textRole(.title)
                        .foregroundStyle(Theme.text)
                    properties(bud)
                    bodyEditor
                    inside(bud)
                    LinkedFrom(id: id, store: store)
                    enrichField(bud)
                }
                .pageColumn()
            }
            #if os(iOS)
            // On iPhone the keyboard covers the page: Done, or a drag down the page, ends the edit.
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if bodyFocused {
                    // The keyboard covers the page, so the [[ picker rides above it with Done.
                    VStack(alignment: .leading, spacing: 6) {
                        if let picker = linkPicker { pickerList(picker) }
                        HStack {
                            Spacer()
                            Button("Done") { bodyFocused = false }
                                .buttonStyle(.budGhost)
                                .accessibilityIdentifier("body-done")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Theme.surface)
                }
            }
            #endif
            .background {
                // ⌘↩ closes or reopens this bud, drawn nowhere.
                Button("") { store.tick(id) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .opacity(0)
            }
            .onAppear { draft = bud.body }
            .onChange(of: bud.body) { _, now in if !dirty { draft = now } }
            .onChange(of: draft) { old, now in
                scheduleSave()
                let typed = LinkPicker(typing: now)
                armed = typed?.edited(from: old, to: now) ?? false
                if typed?.range.lowerBound != closedAt { closedAt = nil }
            }
            .onChange(of: editing) { _, _ in closedAt = nil; armed = false }
            .onDisappear { flush() }
        }
    }

    // MARK: doc bar

    private func docBar(_ bud: Bud) -> some View {
        HStack(spacing: 12) {
            Text(store.tree.filePath(of: id))
                .textRole(.mono)
                .lineLimit(1)
                .truncationMode(.head)
                .foregroundStyle(Theme.text3)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: dirty ? "circle.dotted" : "checkmark.circle.fill")
                    .foregroundStyle(dirty ? Theme.text3 : Theme.leaf)
                Text(dirty ? "Saving…" : "Saved")
                    .foregroundStyle(Theme.text3)
            }
            .textRole(.caption)
            Button {
                flush()
                withAnimation(.spring(duration: 0.8, bounce: 0.12)) { store.center = id }
                store.surface = .canvas
            } label: {
                Image(systemName: "circle.dotted")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.leaf)
            .help("Show on the canvas")
        }
    }

    // MARK: properties

    private func properties(_ bud: Bud) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PropertyRow(name: "State") {
                if bud.isTodo {
                    Segmented(selection: Binding(get: { bud.isDone }, set: { _ in store.tick(id) }), options: [false, true]) { $0 ? "Done" : "Open" }
                } else {
                    Button("Make a to-do") { store.update(id, text: bud.text, todo: true) }
                        .buttonStyle(.bordered)
                        .textRole(.label)
                }
            }
            PropertyRow(name: "When") { DateField(label: "When", date: bud.when) { store.setWhen(id, $0) } }
            PropertyRow(name: "Due") { DateField(label: "Due", date: bud.due) { store.setDue(id, $0) } }
            PropertyRow(name: "Pinned") {
                Button(bud.pinned ? "Pinned" : "Pin", systemImage: bud.pinned ? "pin.fill" : "pin") { store.setPinned(id, !bud.pinned) }
                    .buttonStyle(.bordered)
                    .textRole(.label)
            }
        }
    }

    // MARK: body

    /// Reading, the body is a page: headings, bullets, bold, links; a click opens the plain
    /// editor with the source in its place, and the page returns when the editor loses focus.
    @ViewBuilder private var bodyEditor: some View {
        if editing {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $draft)
                    .textRole(.body)
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 160)
                    .focused($bodyFocused)
                    .onAppear { bodyFocused = true }
                    .onChange(of: bodyFocused) { _, now in if !now { editing = false; flush() } }
                    .onChange(of: linkPicker?.query) { _, _ in pick = 0 }
                    #if os(iOS)
                    .scrollDismissesKeyboard(.never)
                    #endif
                    .onKeyPress(keys: [.upArrow, .downArrow, .return, .tab, .escape]) { press in
                        press.modifiers.isEmpty && pickerKey(press.key) ? .handled : .ignored
                    }
                #if !os(iOS)
                if let picker = linkPicker { pickerList(picker) }
                #endif
            }
        } else {
            Group {
                if draft.isEmpty {
                    Text(Self.emptyBody)
                        .foregroundStyle(Theme.text3)
                } else {
                    RenderedBody(source: draft, tree: store.tree) { store.center = $0 }
                }
            }
            .textRole(.body)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .contentShape(Rectangle())
            // Beside the links in the text, not over them: a click on a link opens its bud.
            .simultaneousGesture(TapGesture().onEnded { editing = true })
        }
    }

    #if os(iOS)
    static let emptyBody = "Nothing written yet. Tap to write."
    #else
    static let emptyBody = "Nothing written yet. Click to write."
    #endif

    // MARK: link picker

    /// The link being typed while the editor is open, unless Esc closed the picker on it. A
    /// `[[` left open in the text from before does not open it: only typing does.
    private var linkPicker: LinkPicker? {
        guard editing, armed, let picker = LinkPicker(typing: draft), picker.range.lowerBound != closedAt else { return nil }
        return picker
    }

    private func pickerList(_ picker: LinkPicker) -> some View {
        LinkPickerList(
            rows: pickerRows(picker), pick: pick, tree: store.tree, here: store.tree.title(of: id)
        ) { row in choose(row, labelled: false) }
    }

    /// The buds the link could name, then planting one when no title is the query.
    private func pickerRows(_ picker: LinkPicker) -> [LinkPickerList.Row] {
        let found = picker.candidates(in: store.tree, excluding: id)
        let query = picker.query.trimmingCharacters(in: .whitespaces)
        let taken = store.tree.buds.contains { BudLinks.fold($0.text) == BudLinks.fold(query) }
        let plant = !query.isEmpty && LinkPicker.linkable(query) && !taken
        return found.map { .bud($0) } + (plant ? [.plant(query)] : [])
    }

    /// ↑↓ move the pick, ↩ links, ⇥ links with the typed text as its label, Esc closes.
    private func pickerKey(_ key: KeyEquivalent) -> Bool {
        guard armed, let picker = linkPicker else { return false }
        let rows = pickerRows(picker)
        switch key {
        case .escape: closedAt = picker.range.lowerBound
        case .upArrow: pick = max(0, pick - 1)
        case .downArrow: pick = max(0, min(rows.count - 1, pick + 1))
        default:
            guard rows.indices.contains(pick) else { return false }
            choose(rows[pick], labelled: key == .tab)
        }
        return true
    }

    private func choose(_ row: LinkPickerList.Row, labelled: Bool) {
        guard let picker = linkPicker else { return }
        switch row {
        case .bud(let target):
            draft = picker.complete(draft, with: LinkPicker.target(for: target, in: store.tree), labelled: labelled)
        case .plant(let title):
            guard let planted = store.add(title, todo: false, under: id) else { return }
            draft = picker.complete(draft, with: LinkPicker.target(for: planted, in: store.tree))
        }
        pick = 0
        bodyFocused = true
    }

    private func scheduleSave() {
        guard draft != store.tree.bud(id)?.body else { return }
        dirty = true
        saver?.cancel()
        saver = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    private func flush() {
        saver?.cancel()
        guard dirty else { return }
        store.setBody(id, draft)
        dirty = false
    }

    // MARK: inside

    private func inside(_ bud: Bud) -> some View {
        let kids = store.tree.children(of: id)
        let shown = kids.filter { !$0.isDone }
        let hidden = kids.count - shown.count
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("INSIDE · \(kids.count)")
                    .textRole(.eyebrow)
                    .foregroundStyle(Theme.text3)
                if hidden > 0 {
                    Text("\(hidden) closed hidden")
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                }
            }
            .padding(.bottom, 4)
            ForEach(shown) { child in
                Button { store.center = child.id } label: {
                    PageRow(bud: child, tree: store.tree)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func enrichField(_ bud: Bud) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .foregroundStyle(Theme.text3)
            TextField("Enrich \(bud.text)…", text: $enrich)
                .textFieldStyle(.plain)
                .onSubmit {
                    store.add(enrich, todo: store.tree.suggestsTodo(under: id), under: id)
                    enrich = ""
                }
        }
        .textRole(.body)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }
}

/// The buds whose body links to a page, each with where it lives and the sentence the link
/// sits in; a click goes to that bud. Nothing is drawn while no bud links here. A view of its
/// own, so typing in the page's body does not read every bud again.
struct LinkedFrom: View {
    let id: UUID
    @ObservedObject var store: BudStore

    var body: some View {
        let links = store.tree.backlinks(to: id)
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("LINKED FROM · \(links.count)")
                        .textRole(.eyebrow)
                        .foregroundStyle(Theme.text3)
                    Spacer()
                    Text("Rename keeps these links")
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                }
                ForEach(links) { link in
                    Button { store.center = link.from } label: {
                        BacklinkRow(link: link, tree: store.tree)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// The `[[` picker under the editor: the buds the link could name with where each lives, then
/// planting the typed title under this bud, and the keys it answers to.
struct LinkPickerList: View {
    enum Row: Hashable {
        case bud(Bud)
        case plant(String)
    }

    let rows: [Row]
    let pick: Int
    let tree: Tree
    /// The title of the bud being written in, for the plant row.
    let here: String
    let choose: (Row) -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                Button { choose(row) } label: {
                    line(row, picked: index == pick)
                }
                .buttonStyle(.plain)
            }
            if rows.isEmpty {
                Text("No bud has that title.")
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
                    .padding(8)
            }
            if Self.hasKeys {
                Divider()
                Text("↑↓ choose · ↩ link · ⇥ link with a label · esc close")
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
        }
        .padding(6)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Theme.raised, in: shape)
        .overlay(shape.stroke(Theme.line, lineWidth: 1))
        .accessibilityIdentifier("link-picker")
    }

    /// Whether the keys in the hint work: always on the Mac; on iPhone and iPad only with a
    /// hardware keyboard attached.
    private static var hasKeys: Bool {
        #if os(iOS)
        GCKeyboard.coalesced != nil
        #else
        true
        #endif
    }

    @ViewBuilder private func line(_ row: Row, picked: Bool) -> some View {
        HStack(spacing: 10) {
            switch row {
            case .bud(let bud):
                Image(systemName: bud.isTodo ? "square" : "doc.text")
                    .foregroundStyle(Theme.text2)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(bud.text)
                        .textRole(.label)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(tree.trail(of: bud.id).joined(separator: " › "))
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                        .lineLimit(1)
                }
            case .plant(let title):
                Image(systemName: "leaf")
                    .foregroundStyle(Theme.leaf)
                    .frame(width: 18)
                Text("Plant “\(title)” under \(here)")
                    .textRole(.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.leaf)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(picked ? Theme.leafSoft : .clear, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// One "Linked from" row: the linking bud and where it lives, the sentence below with the link
/// marked in leaf.
struct BacklinkRow: View {
    let link: Backlink
    let tree: Tree

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward")
                    .foregroundStyle(Theme.leaf)
                Text(tree.title(of: link.from))
                    .textRole(.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
                Text(tree.trail(of: link.from).joined(separator: " › "))
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundStyle(Theme.text3)
            }
            Text(marked)
                .textRole(.body)
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Theme.raised, in: shape)
        .overlay(shape.stroke(Theme.line, lineWidth: 1))
        .contentShape(shape)
    }

    private var marked: AttributedString {
        var text = AttributedString(link.sentence)
        guard link.mark.upperBound <= text.characters.count, !link.mark.isEmpty else { return text }
        let lower = text.index(text.startIndex, offsetByCharacters: link.mark.lowerBound)
        let upper = text.index(lower, offsetByCharacters: link.mark.count)
        text[lower..<upper].foregroundColor = Theme.leaf
        text[lower..<upper].backgroundColor = Theme.leafSoft
        return text
    }
}

/// The body as a page: each block from `MarkdownBlocks` drawn in the type scale, links in
/// amethyst and clickable, paragraphs with 1.55 line height. A `[[link]]` to a bud reads in leaf
/// with the link icon and a click opens that bud; one that names no bud reads grey, dotted, with
/// a dashed circle.
struct RenderedBody: View {
    let source: String
    var tree: Tree?
    var open: (UUID) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(MarkdownBlocks.parse(source).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    readable(linked(text), text)
                        .tint(tint(for: text))
                        .textRole(level == 1 ? .title : .heading)
                        .foregroundStyle(Theme.text)
                        .padding(.top, level == 1 ? 4 : 2)
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle()
                                    .fill(Theme.leaf)
                                    .frame(width: 5, height: 5)
                                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 3 }
                                paragraph(item)
                            }
                            .padding(.leading, 4)
                        }
                    }
                case .paragraph(let text):
                    paragraph(text)
                }
            }
        }
        .tint(Theme.amethyst)
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == Self.scheme, let id = url.host().flatMap(UUID.init(uuidString:)) else { return .systemAction }
            open(id)
            return .handled
        })
    }

    private static let scheme = "bud"

    /// Text draws every link in its tint: a line with a link to a bud tints its links leaf.
    private func tint(for text: String) -> Color {
        let toBud = BudLinks.runs(text).contains { run in
            if case .link(let link) = run { return tree?.resolve(link.target) != nil }
            return false
        }
        return toBud ? Theme.leaf : Theme.amethyst
    }

    /// One line of text with its `[[links]]` drawn as links to buds.
    private func linked(_ text: String) -> Text {
        var out = Text("")
        for run in BudLinks.runs(text) {
            switch run {
            case .text(let plain):
                out = out + Text(MarkdownBlocks.inline(plain))
            case .link(let link):
                var shown = AttributedString(link.shown)
                if let id = tree?.resolve(link.target) {
                    // The arrow is characters carrying the link too, not an image beside it: an
                    // image cannot carry the link, so a tap on it fell through to the editor.
                    // VoiceOver reads the words alone.
                    let url = URL(string: "\(Self.scheme)://\(id.uuidString)")
                    var arrow = AttributedString("\u{00A0}\u{2197}")
                    shown.link = url
                    arrow.link = url
                    shown.foregroundColor = Theme.leaf
                    arrow.foregroundColor = Theme.leaf
                    out = out + Text(shown).fontWeight(.semibold) + Text(arrow).fontWeight(.semibold).accessibilityLabel("")
                } else {
                    shown.foregroundColor = Theme.text3
                    shown.underlineStyle = Text.LineStyle(pattern: .dot, color: Theme.text3)
                    out = out + Text(shown) + Text("\u{00A0}") + Text(Image(systemName: "circle.dashed")).foregroundStyle(Theme.text3).accessibilityLabel(", no such bud")
                }
            }
        }
        return out
    }

    /// A line with an action to open each bud it links to, beside the links VoiceOver lists.
    private func readable(_ line: Text, _ text: String) -> some View {
        var seen: Set<UUID> = []
        let targets: [(String, UUID)] = BudLinks.runs(text).compactMap { run in
            guard case .link(let link) = run, let id = tree?.resolve(link.target), seen.insert(id).inserted else { return nil }
            return (tree?.title(of: id) ?? link.shown, id)
        }
        return line
            .accessibilityActions {
                ForEach(Array(targets.enumerated()), id: \.offset) { _, target in
                    Button("Open \(target.0)") { open(target.1) }
                }
            }
    }

    private func paragraph(_ text: String) -> some View {
        readable(linked(text), text)
            .tint(tint(for: text))
            .textRole(.body)
            .lineSpacing(14 * 0.55)
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
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

/// One property of the document: its name in the gutter, its control beside it.
struct PropertyRow<Control: View>: View {
    let name: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(name)
                .textRole(.label)
                .foregroundStyle(Theme.text2)
                .frame(width: 64, alignment: .leading)
            control()
            Spacer()
        }
    }
}
#endif
