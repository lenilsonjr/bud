#if canImport(SwiftUI)
import SwiftUI

struct EditTarget: Identifiable {
    let id: UUID
}

struct AddTarget: Identifiable {
    let parent: UUID
    var id: UUID { parent }
}

struct AddSheet: View {
    @ObservedObject var store: BudStore
    let parent: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var todo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New bud under \(store.tree.title(of: parent))")
                .font(.headline)
            TextField("What is it?", text: $text)
                .textFieldStyle(.roundedBorder)
            Picker("Kind", selection: $todo) {
                Text("Note").tag(false)
                Text("To-do").tag(true)
            }
            .pickerStyle(.segmented)
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") {
                    store.add(text.trimmingCharacters(in: .whitespacesAndNewlines), todo: todo, under: parent)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
    }
}

struct EditSheet: View {
    @ObservedObject var store: BudStore
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var todo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit bud")
                .font(.headline)
            TextField("Text", text: $text)
                .textFieldStyle(.roundedBorder)
            Picker("Kind", selection: $todo) {
                Text("Note").tag(false)
                Text("To-do").tag(true)
            }
            .pickerStyle(.segmented)
            HStack {
                Button("Delete", role: .destructive) {
                    store.remove(id)
                    dismiss()
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    store.update(id, text: text.trimmingCharacters(in: .whitespacesAndNewlines), todo: todo)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
        .onAppear {
            if let bud = store.tree.bud(id) {
                text = bud.text
                todo = bud.isTodo
            }
        }
    }
}
#endif
