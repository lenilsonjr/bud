#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The soil on a compact width: a bottom sheet with one source at a time. Each item's Plant opens
/// the Move picker, the Inbox first, since there is no canvas room to drag it up.
struct PhoneSoilSheet: View {
    @ObservedObject var store: BudStore
    @State private var shown: String?
    @State private var planting: Pick?
    @Environment(\.stillPicture) private var still

    struct Pick: Identifiable {
        let item: SourceItem
        let account: SourceAccount
        var id: String { account.kind.key(item.id) }
    }

    var body: some View {
        let roots = store.roots()
        let root = roots.first { $0.id == shown } ?? roots.first
        VStack(alignment: .leading, spacing: 12) {
            // A still picture draws nothing inside a scroll view.
            if still {
                tabs(roots, on: root?.id)
            } else {
                ScrollView(.horizontal, showsIndicators: false) { tabs(roots, on: root?.id) }
            }
            if let root {
                list(root)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.sidebar)
        .sheet(item: $planting) { planting in
            MoveToPicker(store: store, planting: planting.item, from: planting.account)
        }
        .accessibilityIdentifier("phone-soil")
    }

    private func tabs(_ roots: [Root], on id: String?) -> some View {
        HStack(spacing: 8) {
            ForEach(roots) { each in
                Button { shown = each.id } label: { tab(each, on: each.id == id) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func tab(_ root: Root, on: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: SoilView.symbol(root.account.kind))
            Text(root.account.name).textRole(.label)
            if root.account.locked {
                Image(systemName: "lock.fill").font(.system(size: 9))
            } else if root.leaf {
                Circle().fill(Theme.leaf).frame(width: 6, height: 6)
            }
        }
        .foregroundStyle(on ? Theme.onLeaf : Theme.text2)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(on ? Theme.leaf : Theme.raised, in: Capsule())
        .overlay(Capsule().stroke(on ? .clear : Theme.line, lineWidth: 1))
    }

    @ViewBuilder private func list(_ root: Root) -> some View {
        if root.account.locked {
            Button { store.modal = .connectMail(account: root.id) } label: {
                Label("Sign in on this \(BudStore.deviceName)", systemImage: "lock.fill")
            }
            .buttonStyle(.budSecondary)
        } else {
            let items = Root.order(root.account.items, kind: root.account.kind, now: Date())
            MaybeScroll {
                VStack(spacing: 6) {
                    ForEach(items) { item in
                        row(item, in: root.account)
                    }
                    if items.isEmpty {
                        Text("Nothing here right now.")
                            .textRole(.body)
                            .foregroundStyle(Theme.text3)
                    }
                }
            }
        }
    }

    private func row(_ item: SourceItem, in account: SourceAccount) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return HStack(spacing: 10) {
            if Root.needsYou(item, kind: account.kind, now: Date()) {
                Circle().fill(Theme.leaf).frame(width: 6, height: 6)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).textRole(.cardTitle).foregroundStyle(Theme.cardInk).lineLimit(2)
                if let detail = item.detail {
                    Text(detail).textRole(.caption).foregroundStyle(Theme.cardMeta).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button("Plant") { planting = Pick(item: item, account: account) }
                .buttonStyle(.budGhost)
                .accessibilityIdentifier("plant-\(item.id)")
        }
        .padding(10)
        .background(Theme.card, in: shape)
        .overlay(shape.stroke(Theme.cardLine, lineWidth: 1))
    }
}
#endif
