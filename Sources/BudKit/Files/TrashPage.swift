#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The Trash: every branch trashed and not yet restored or deleted, newest first. Restore puts a
/// branch back where it was; Delete and Empty trash ask first, since nothing undoes them.
struct TrashPage: View {
    @ObservedObject var store: BudStore

    var body: some View {
        let branches = store.tree.trashed.reversed()
        MaybeScroll {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PLACE")
                        .textRole(.eyebrow)
                        .foregroundStyle(Theme.leaf)
                    Text("Trash")
                        .textRole(.title)
                        .foregroundStyle(Theme.text)
                    Text(branches.count == 1 ? "1 branch" : "\(branches.count) branches")
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                }
                if branches.isEmpty {
                    Text("Nothing in the trash. A trashed branch waits here until you restore it or delete it for good.")
                        .textRole(.body)
                        .foregroundStyle(Theme.text3)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(branches)) { branch in
                            row(branch)
                        }
                    }
                    HStack {
                        Spacer()
                        Button { store.modal = .deleteForever(id: nil) } label: { BudButtonLabel(title: "Empty trash") }
                            .buttonStyle(.budSecondary)
                    }
                }
            }
            .pageColumn()
        }
    }

    private func row(_ branch: TrashedBranch) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "trash")
                .textRole(.caption)
                .foregroundStyle(Theme.text3)
                .frame(width: 16, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(branch.head.text)
                    .textRole(.body)
                    .foregroundStyle(Theme.text)
                Text(Self.caption(branch))
                    .textRole(.caption)
                    .foregroundStyle(Theme.text3)
            }
            Spacer()
            Button("Restore") { store.restore(branch.id) }
                .buttonStyle(.bordered)
            Button("Delete") { store.modal = .deleteForever(id: branch.id) }
                .buttonStyle(.bordered)
                .tint(Theme.rose)
        }
        .textRole(.label)
        .padding(.vertical, 10)
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .rowHairline()
        .contentShape(Rectangle())
    }

    /// "Trashed Today · 09:14 · 3 inside"; a lone bud has no count.
    static func caption(_ branch: TrashedBranch, now: Date = Date()) -> String {
        let day = Tree.dayLabel(for: branch.at, now: now)
        let time = branch.at.formatted(date: .omitted, time: .shortened)
        var parts = ["Trashed \(day) · \(time)"]
        if branch.inside > 0 { parts.append(branch.inside == 1 ? "1 inside" : "\(branch.inside) inside") }
        return parts.joined(separator: " · ")
    }
}

/// Delete for good: one branch, or the whole Trash. Esc keeps it, Return deletes.
struct DeleteForeverDialog: View {
    @ObservedObject var store: BudStore
    /// The branch, or nil for everything in the Trash.
    let id: UUID?

    private static let title = TextStyle(typeface: .display, size: 24, weight: 500)
    private static let body = TextStyle(typeface: .text, size: 13, weight: 400)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(heading)
                .textStyle(Self.title)
                .foregroundStyle(Theme.text)
            Text(explanation)
                .textStyle(Self.body)
                .lineSpacing(13 * 0.5)
                .foregroundStyle(Theme.text2)
            HStack(spacing: 8) {
                Spacer()
                Button { store.modal = nil } label: { BudButtonLabel(title: "Keep") }
                    .buttonStyle(.budSecondary)
                    .keyboardShortcut(.cancelAction)
                Button(action: delete) { BudButtonLabel(title: id == nil ? "Empty trash" : "Delete") }
                    .buttonStyle(.budDestructive)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .textRole(.body)
        .tint(Theme.leaf)
    }

    private var branch: TrashedBranch? { id.flatMap { id in store.tree.trashed.first { $0.id == id } } }

    private var heading: String {
        if let branch { return "Delete \(branch.head.text)?" }
        return "Empty the trash?"
    }

    private var explanation: String {
        if let branch {
            let inside = branch.inside
            return inside == 0
                ? "It goes for good. Nothing brings it back."
                : "It and the \(inside) \(inside == 1 ? "bud" : "buds") inside go for good. Nothing brings them back."
        }
        let count = store.tree.trashed.count
        return "\(count == 1 ? "1 branch goes" : "\(count) branches go") for good. Nothing brings them back."
    }

    private func delete() {
        if let id { store.deleteForever(id) } else { store.emptyTrash() }
        store.modal = nil
    }
}
#endif
