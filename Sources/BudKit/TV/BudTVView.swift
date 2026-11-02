#if canImport(SwiftUI) && os(tvOS)
import SwiftUI

/// Bud on Apple TV: the children of the current bud as a row of cards for the remote, a trail
/// back to Everything, one line of capture, and Play/Pause to tick a to-do. No canvas here.
public struct BudTVView: View {
    @StateObject private var store: BudStore
    @State private var capturing = false
    @FocusState private var focusedCard: UUID?

    @MainActor public init(fileURL: URL? = BudStore.defaultFile) {
        _store = StateObject(wrappedValue: BudStore(fileURL: fileURL))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            trail
            cards
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.canvas)
        .textRole(.body)
        .foregroundStyle(Theme.text)
        .onExitCommand { stepOut() }
        .onPlayPauseCommand { toggleFocused() }
        .sheet(isPresented: $capturing) { TVCaptureSheet(store: store, parent: store.center) }
    }

    // MARK: where you are

    private var trail: some View {
        HStack(spacing: 14) {
            ForEach(Array(store.centerTrail.enumerated()), id: \.offset) { index, id in
                if index > 0 {
                    Text("›").foregroundStyle(Theme.text3)
                }
                Text(store.tree.title(of: id))
                    .textRole(index == store.centerTrail.count - 1 ? .title : .heading)
                    .foregroundStyle(index == store.centerTrail.count - 1 ? Theme.text : Theme.text2)
            }
            Spacer()
            Button {
                capturing = true
            } label: {
                Label("Capture", systemImage: "plus")
            }
            .textRole(.label)
        }
    }

    // MARK: the row

    private var children: [Bud] { store.tree.children(of: store.center) }

    @ViewBuilder private var cards: some View {
        if children.isEmpty {
            Text("Nothing here yet. Capture a thought to plant the first bud.")
                .textRole(.heading)
                .foregroundStyle(Theme.text3)
                .padding(.top, 40)
        } else {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 36) {
                    ForEach(children) { bud in
                        Button {
                            open(bud)
                        } label: {
                            TVCard(bud: bud, children: store.tree.children(of: bud.id).count, open: store.tree.openCount(under: bud.id))
                        }
                        .buttonStyle(.card)
                        .focused($focusedCard, equals: bud.id)
                    }
                }
                .padding(.vertical, 40)
                .padding(.horizontal, 20)
            }
            .scrollClipDisabled()
        }
    }

    private var footer: some View {
        Text("Click a bud with children to go in. Menu steps out. Play/Pause ticks the to-do in focus. What you plant here stays on this TV until sync arrives.")
            .textRole(.caption)
            .foregroundStyle(Theme.text3)
    }

    // MARK: moves

    private func open(_ bud: Bud) {
        if store.tree.hasChildren(bud.id) {
            withAnimation(.easeInOut(duration: 0.3)) { store.center = bud.id }
        } else if bud.isTodo {
            store.toggle(bud.id)
        }
    }

    private func toggleFocused() {
        guard let id = focusedCard, store.tree.bud(id)?.isTodo == true else { return }
        store.toggle(id)
    }

    private func stepOut() {
        guard store.center != rootID else { return }
        withAnimation(.easeInOut(duration: 0.3)) { store.back() }
    }
}

/// One card in the row: the kind mark, the title, and what it holds.
struct TVCard: View {
    let bud: Bud
    let children: Int
    let open: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if bud.isTodo {
                    Image(systemName: bud.isDone ? "checkmark.square.fill" : "square")
                        .foregroundStyle(bud.isDone ? Theme.leaf : meta)
                } else {
                    Circle().fill(Theme.leaf).frame(width: 10, height: 10)
                }
                Text(subtitle)
                    .textRole(.label)
                    .foregroundStyle(meta)
            }
            Text(bud.text)
                .strikethrough(bud.isDone)
                .textRole(.heading)
                .foregroundStyle(bud.isDone ? meta : ink)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 360, height: 200, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(line, lineWidth: 2))
    }

    private var subtitle: String {
        if children == 0 { return bud.isTodo ? (bud.isDone ? "Done" : "To-do") : "Note" }
        return "\(children) inside" + (open > 0 ? " · \(open) open" : "")
    }

    private var ink: Color { Theme.cardInk }
    private var meta: Color { bud.isTodo ? Theme.cardMeta : Theme.cardNoteMeta }
    private var fill: Color { bud.isTodo ? Theme.card : Theme.cardNote }
    private var line: Color { bud.isTodo ? Theme.cardLine : Theme.cardNoteLine }
}

/// One line of text from the TV keyboard or dictation, planted under the current bud.
struct TVCaptureSheet: View {
    @ObservedObject var store: BudStore
    let parent: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var todo = true

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("New bud under \(store.tree.title(of: parent))")
                .textRole(.title)
                .foregroundStyle(Theme.text)
            TextField("What is it?", text: $text)
                .onSubmit(plant)
            Picker("Kind", selection: $todo) {
                Text("To-do").tag(true)
                Text("Note").tag(false)
            }
            .pickerStyle(.segmented)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Plant", action: plant)
                    .disabled(trimmed.isEmpty)
            }
            .textRole(.label)
        }
        .padding(80)
        .textRole(.body)
        .foregroundStyle(Theme.text)
        .background(Theme.surface)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func plant() {
        guard !trimmed.isEmpty else { return }
        store.add(trimmed, todo: todo, under: parent)
        dismiss()
    }
}
#endif
