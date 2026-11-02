#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The Archive: finished chapters, the threads under Everything that are closed. Nothing is moved
/// here by hand: closing a thread files it, reopening it takes it back out. A tap opens it.
struct ArchivePage: View {
    @ObservedObject var store: BudStore

    var body: some View {
        let threads = store.tree.archived()
        MaybeScroll {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PLACE")
                        .textRole(.eyebrow)
                        .foregroundStyle(Theme.leaf)
                    Text("Archive")
                        .textRole(.title)
                        .foregroundStyle(Theme.text)
                    Text(threads.count == 1 ? "1 finished chapter" : "\(threads.count) finished chapters")
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                }
                if threads.isEmpty {
                    Text("No finished chapters yet. Close a thread and it lands here; reopen it and it goes back.")
                        .textRole(.body)
                        .foregroundStyle(Theme.text3)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(threads) { thread in
                            row(thread)
                        }
                    }
                }
            }
            .pageColumn()
        }
    }

    private func row(_ thread: Bud) -> some View {
        let inside = store.tree.descendants(of: thread.id).count
        let lede = store.tree.lede(of: thread.id)
        return HStack(alignment: .top, spacing: 8) {
            RowMark(bud: thread, onTick: { store.tick(thread.id) })
            VStack(alignment: .leading, spacing: 2) {
                Text(thread.text)
                    .textRole(.body)
                    .strikethrough()
                    .foregroundStyle(Theme.text3)
                if !lede.isEmpty {
                    Text(lede)
                        .textRole(.caption)
                        .lineLimit(2)
                        .foregroundStyle(Theme.text3)
                }
            }
            Spacer()
            if inside > 0 {
                NeutralTag(inside == 1 ? "1 inside" : "\(inside) inside")
            }
        }
        .textRole(.label)
        .padding(.vertical, 10)
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .rowHairline()
        .contentShape(Rectangle())
        .onTapGesture { store.openAsFile(thread.id) }
        .budMenu(thread.id, store: store)
    }
}
#endif
