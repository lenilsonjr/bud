#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

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
                    linkedFrom
                    enrichField(bud)
                }
                .pageColumn()
            }
            .background {
                // ⌘↩ closes or reopens this bud, drawn nowhere.
                Button("") { store.tick(id) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .opacity(0)
            }
            .onAppear { draft = bud.body }
            .onChange(of: bud.body) { _, now in if !dirty { draft = now } }
            .onChange(of: draft) { _, _ in scheduleSave() }
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
            TextEditor(text: $draft)
                .textRole(.body)
                .foregroundStyle(Theme.text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 160)
                .focused($bodyFocused)
                .onAppear { bodyFocused = true }
                .onChange(of: bodyFocused) { _, now in if !now { editing = false; flush() } }
        } else {
            Group {
                if draft.isEmpty {
                    Text("Nothing written yet. Click to write.")
                        .foregroundStyle(Theme.text3)
                } else {
                    RenderedBody(source: draft)
                }
            }
            .textRole(.body)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture { editing = true }
        }
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

    // MARK: linked from

    /// The buds whose body links here, each with where it lives and the sentence the link sits
    /// in; a click goes to that bud. Nothing is drawn while no bud links here.
    @ViewBuilder private var linkedFrom: some View {
        let links = store.tree.backlinks(to: id)
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("LINKED FROM · \(links.count)")
                    .textRole(.eyebrow)
                    .foregroundStyle(Theme.text3)
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
                Text((["Everything"] + tree.breadcrumb(of: link.from)).joined(separator: " › "))
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
        if let range = text.range(of: link.shown) {
            text[range].foregroundColor = Theme.leaf
            text[range].backgroundColor = Theme.leafSoft
        }
        return text
    }
}

/// The body as a page: each block from `MarkdownBlocks` drawn in the type scale, links in
/// amethyst and clickable, paragraphs with 1.55 line height.
struct RenderedBody: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(MarkdownBlocks.parse(source).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    Text(MarkdownBlocks.inline(text))
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
    }

    private func paragraph(_ text: String) -> some View {
        Text(MarkdownBlocks.inline(text))
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
