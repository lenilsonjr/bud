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
                }
                .padding(28)
                .frame(maxWidth: 720, alignment: .leading)
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
                .foregroundStyle(Theme.text3)
            Spacer()
            Text(dirty ? "Saving…" : "Saved")
                .textRole(.caption)
                .foregroundStyle(Theme.text3)
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
            PropertyRow(name: "When") { dateField(bud.when) { store.setWhen(id, $0) } }
            PropertyRow(name: "Due") { dateField(bud.due) { store.setDue(id, $0) } }
            PropertyRow(name: "Pinned") {
                Button(bud.pinned ? "Pinned" : "Pin", systemImage: bud.pinned ? "pin.fill" : "pin") { store.setPinned(id, !bud.pinned) }
                    .buttonStyle(.bordered)
                    .textRole(.label)
            }
        }
    }

    private func dateField(_ date: Date?, set: @escaping (Date?) -> Void) -> some View {
        HStack(spacing: 8) {
            if let date {
                DatePicker("", selection: Binding(get: { date }, set: { set($0) }), displayedComponents: .date)
                    .labelsHidden()
                Button("Clear") { set(nil) }
                    .buttonStyle(.plain)
                    .textRole(.label)
                    .foregroundStyle(Theme.text3)
            } else {
                Button("Set a day") { set(Calendar.current.startOfDay(for: Date())) }
                    .buttonStyle(.bordered)
                    .textRole(.label)
            }
        }
    }

    // MARK: body

    /// Reading, the body shows with headings, bullets, bold and links coloured; a click opens the
    /// plain editor in its place, and the colours return when the editor loses focus.
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
                    Text(highlighted(draft))
                }
            }
            .textRole(.body)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture { editing = true }
        }
    }

    private func highlighted(_ text: String) -> AttributedString {
        var out = AttributedString(text)
        out.foregroundColor = Theme.text
        for span in MarkdownHighlighter.spans(in: text) {
            guard let lower = AttributedString.Index(String.Index(utf16Offset: span.range.lowerBound, in: text), within: out),
                  let upper = AttributedString.Index(String.Index(utf16Offset: span.range.upperBound, in: text), within: out)
            else { continue }
            switch span.kind {
            case .heading:
                out[lower..<upper].font = Theme.font(.heading)
            case .bullet:
                out[lower..<upper].foregroundColor = Theme.leaf
            case .bold:
                out[lower..<upper].font = Theme.font(.cardTitle)
            case .link:
                out[lower..<upper].foregroundColor = Theme.amethyst
            }
        }
        return out
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
