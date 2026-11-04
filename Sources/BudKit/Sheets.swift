#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// What the sheet is for: enrich plants a bud under the one you are looking at, capture takes one
/// line with no place in mind and lands it in the Inbox.
enum AddMode: Hashable {
    case enrich(under: UUID)
    case capture
}

/// The quick add sheet: one line and a kind, Return plants it, Esc cancels. Opened by the + on a
/// card or the N key for the lit card, on Everything too. In capture mode, opened by the capture
/// button at the top right, it has no kind: a capture is a note until it is enriched.
struct AddSheet: View {
    @ObservedObject var store: BudStore
    let mode: AddMode
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
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Theme.canvas, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).stroke(typing ? Theme.leafLine : Theme.lineStrong, lineWidth: 1))
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
            HStack(spacing: 8) {
                Keycap("Esc")
                Spacer()
                Button { close() } label: { BudButtonLabel(title: "Cancel") }
                    .buttonStyle(.budSecondary)
                    .keyboardShortcut(.cancelAction)
                Button(action: plant) { BudButtonLabel(title: capturing ? "Capture" : "Add") }
                    .buttonStyle(.budPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(line.isEmpty)
            }
        }
        .textRole(.body)
        .tint(Theme.leaf)
        .onAppear {
            if case .enrich(let parent) = mode { todo = store.tree.suggestsTodo(under: parent) }
            typing = true
        }
    }

    private func close() { store.modal = nil }

    private var heading: String {
        switch mode {
        case .enrich(let parent): return PlantTarget.under(parent).title(in: store.tree)
        case .capture: return "Capture"
        }
    }

    private func plant() {
        guard !line.isEmpty else { return }
        switch mode {
        case .enrich(let parent): store.add(line, todo: todo, under: parent)
        case .capture: store.capture(line)
        }
        close()
    }
}
#endif
