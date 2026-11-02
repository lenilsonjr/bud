#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The Inbox for now: a plain list of what was captured, in reading order, each row with a
/// Move to… button. Grouping, filters and the footer are the full Inbox page.
struct InboxPage: View {
    @ObservedObject var store: BudStore
    @State private var moving: Bud? = nil

    var body: some View {
        let buds = store.tree.inbox()
        MaybeScroll {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Inbox")
                        .textRole(.title)
                        .foregroundStyle(Theme.text)
                    Text(buds.count == 1 ? "1 capture" : "\(buds.count) captures")
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                }
                if buds.isEmpty {
                    Text("Nothing waiting. Capture a line and it lands here.")
                        .textRole(.body)
                        .foregroundStyle(Theme.text3)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(buds) { bud in
                            row(bud)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .sheet(item: $moving) { bud in
            MoveToPicker(store: store, bud: bud)
        }
    }

    private func row(_ bud: Bud) -> some View {
        HStack(alignment: .top, spacing: 8) {
            KindMark(bud: bud, style: CardStyle.chip(for: bud, lit: false))
            VStack(alignment: .leading, spacing: 2) {
                Text(bud.text)
                    .textRole(.body)
                    .foregroundStyle(Theme.text)
                if let source = bud.source {
                    Text("from \(source)")
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                }
            }
            Spacer()
            Button("Move to…") { moving = bud }
                .buttonStyle(.bordered)
                .textRole(.label)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }
}
#endif
