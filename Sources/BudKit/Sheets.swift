#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// What the sheet is for: enrich plants a bud under the one you are looking at, capture takes one
/// line with no place in mind and lands it in the Inbox.
enum AddMode: Hashable {
    case enrich(under: UUID)
    case capture
}

struct AddTarget: Identifiable {
    let mode: AddMode

    init(parent: UUID) { mode = .enrich(under: parent) }
    private init(mode: AddMode) { self.mode = mode }

    static let capture = AddTarget(mode: .capture)

    var id: UUID {
        switch mode {
        case .enrich(let parent): return parent
        case .capture: return inboxID
        }
    }
}

/// The quick add sheet: one line and a kind, Return plants it, Esc cancels. Opened by the + on a
/// card or the N key for the lit card. In capture mode, opened by Add here in the bar or the
/// hub's Capture button, it has no kind: a capture is a note until it is enriched.
struct AddSheet: View {
    @ObservedObject var store: BudStore
    let mode: AddMode
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var todo = false
    @FocusState private var typing: Bool

    init(store: BudStore, mode: AddMode) {
        self.store = store
        self.mode = mode
    }

    init(store: BudStore, parent: UUID) {
        self.init(store: store, mode: .enrich(under: parent))
    }

    private var line: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var capturing: Bool { mode == .capture }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(heading)
                    .textRole(.heading)
                    .foregroundStyle(Theme.text)
                Text(capturing ? "Lands in the Inbox. Give it a home later." : "One line is enough. Details can come later.")
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
            }
            TextField("What is it?", text: $text)
                .textFieldStyle(.plain)
                .textRole(.body)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).stroke(typing ? Theme.leafLine : Theme.line, lineWidth: 1))
                .focused($typing)
                .onSubmit(plant)
            if !capturing {
                HStack(spacing: 12) {
                    Text("Kind")
                        .textRole(.label)
                        .foregroundStyle(Theme.text2)
                    Segmented(selection: $todo, options: [false, true]) { $0 ? "To-do" : "Note" }
                }
            }
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(capturing ? "Capture" : "Add", action: plant)
                    .keyboardShortcut(.defaultAction)
                    .disabled(line.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
        .textRole(.body)
        .background(Theme.surface)
        .tint(Theme.leaf)
        .onAppear {
            if case .enrich(let parent) = mode { todo = store.tree.suggestsTodo(under: parent) }
            typing = true
        }
    }

    private var heading: String {
        switch mode {
        case .enrich(let parent): return "New bud under \(store.tree.title(of: parent))"
        case .capture: return "Capture"
        }
    }

    private func plant() {
        guard !line.isEmpty else { return }
        switch mode {
        case .enrich(let parent): store.add(line, todo: todo, under: parent)
        case .capture: store.capture(line)
        }
        dismiss()
    }
}
#endif
