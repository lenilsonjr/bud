#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// A card opened in place: the title to edit, a status tag, a peek at what is inside, and two
/// ways on: Enrich plants a bud under it, Open as file jumps to it in the Files view.
struct DetailCard: View {
    let id: UUID
    @ObservedObject var store: BudStore
    let onEnrich: () -> Void
    let onClose: () -> Void
    @State private var title = ""
    @FocusState private var editingTitle: Bool

    static let width: CGFloat = 264

    var body: some View {
        if let bud = store.tree.bud(id) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    KindMark(bud: bud, style: CardStyle.chip(for: bud, lit: false))
                    TextField("Untitled", text: $title, axis: .vertical)
                        .textFieldStyle(.plain)
                        .textRole(.heading)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1...3)
                        .focused($editingTitle)
                        .onSubmit(save)
                    Button(action: { store.remove(id); onClose() }) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .textRole(.label)
                    .foregroundStyle(Theme.text3)
                    .help("Delete this bud and everything under it")
                }
                statusTag(bud)
                peek(bud)
                HStack(spacing: 8) {
                    Button("Enrich", systemImage: "plus", action: onEnrich)
                    Button("Open as file", systemImage: "doc.text") { store.openAsFile(id) }
                }
                .buttonStyle(.bordered)
                .textRole(.label)
            }
            .padding(14)
            .frame(width: Self.width, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Theme.raised)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Theme.lineStrong, lineWidth: 1))
                    .shadow(color: Theme.shadowStrong, radius: 14, y: 6)
            )
            .onAppear { title = bud.text }
            .onChange(of: bud.text) { _, now in title = now }
        }
    }

    private func statusTag(_ bud: Bud) -> some View {
        Button {
            store.tick(id)
        } label: {
            Text(bud.statusLabel)
                .textRole(.eyebrow)
                .foregroundStyle(bud.isDone ? Theme.leaf : Theme.text2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.sidebar, in: Capsule())
                .overlay(Capsule().stroke(bud.isDone ? Theme.leafLine : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!bud.isTodo)
        .help(bud.isTodo ? "Tick or untick" : "")
    }

    @ViewBuilder private func peek(_ bud: Bud) -> some View {
        let lines = store.tree.peek(into: id)
        if lines.isEmpty {
            Text("Nothing inside yet.")
                .textRole(.caption)
                .foregroundStyle(Theme.text3)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text("· " + line)
                        .textRole(.caption)
                        .lineLimit(1)
                        .foregroundStyle(Theme.text2)
                }
                let more = store.tree.children(of: id).count - lines.count
                if more > 0 {
                    Text("and \(more) more")
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                }
            }
        }
    }

    private func save() {
        guard let bud = store.tree.bud(id) else { return }
        let line = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { title = bud.text; return }
        store.update(id, text: line, todo: bud.isTodo)
        editingTitle = false
    }
}
#endif
