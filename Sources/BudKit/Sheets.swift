#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

struct AddTarget: Identifiable {
    let parent: UUID
    var id: UUID { parent }
}

/// The quick add sheet: one line and a kind, Return plants it, Esc cancels. Opened by Add here
/// in the bar, the + on a card, or the N key for the lit card.
struct AddSheet: View {
    @ObservedObject var store: BudStore
    let parent: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var todo = false
    @FocusState private var typing: Bool

    private var line: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New bud under \(store.tree.title(of: parent))")
                    .textRole(.heading)
                    .foregroundStyle(Theme.text)
                Text("One line is enough. Details can come later.")
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
            HStack(spacing: 12) {
                Text("Kind")
                    .textRole(.label)
                    .foregroundStyle(Theme.text2)
                Segmented(selection: $todo, options: [false, true]) { $0 ? "To-do" : "Note" }
            }
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add", action: plant)
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
            todo = store.tree.suggestsTodo(under: parent)
            typing = true
        }
    }

    private func plant() {
        guard !line.isEmpty else { return }
        store.add(line, todo: todo, under: parent)
        dismiss()
    }
}
#endif
