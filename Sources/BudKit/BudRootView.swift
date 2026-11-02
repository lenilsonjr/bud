#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The whole app: the bar across the top, the canvas or the files below it, a hint at the bottom.
public struct BudRootView: View {
    @StateObject private var store: BudStore
    @State private var adding: AddTarget? = nil

    @MainActor public init(fileURL: URL? = BudStore.defaultFile) {
        _store = StateObject(wrappedValue: BudStore(fileURL: fileURL))
    }

    /// For previews and pictures: a store the caller already holds.
    @MainActor init(store: BudStore) {
        _store = StateObject(wrappedValue: store)
    }

    public var body: some View {
        VStack(spacing: 0) {
            TopBar(store: store) { adding = AddTarget(parent: store.center) }
            surface
                .overlay(alignment: .bottom) { hint }
        }
        .background(Theme.window.ignoresSafeArea())
        .textRole(.body)
        .foregroundStyle(Theme.text)
        .tint(Theme.leaf)
        .sheet(item: $adding) { target in AddSheet(store: store, parent: target.parent) }
    }

    @ViewBuilder private var surface: some View {
        switch store.surface {
        case .canvas:
            OrbitCanvas(store: store)
        case .files:
            FilesPlaceholder(store: store)
        }
    }

    private var hint: some View {
        Text("Drag or scroll to move · pinch to zoom · tap a card with children to center it · tap a leaf or press Space to open it · N adds under the lit card · Esc steps out")
            .textRole(.caption)
            .foregroundStyle(Theme.text3)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.glass, in: Capsule())
            .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
            .padding(12)
    }
}

/// Where the Files view will be: the current bud's title and its children as rows.
struct FilesPlaceholder: View {
    @ObservedObject var store: BudStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.tree.title(of: store.center))
                .textRole(.title)
                .foregroundStyle(Theme.text)
            ForEach(store.tree.children(of: store.center)) { bud in
                HStack(spacing: 8) {
                    KindMark(bud: bud, style: CardStyle.chip(for: bud, lit: false))
                    Text(bud.text)
                        .strikethrough(bud.isDone)
                        .foregroundStyle(bud.isDone ? Theme.text3 : Theme.text)
                    Spacer()
                    Text(CardStyle.caption(for: bud, in: store.tree))
                        .textRole(.caption)
                        .foregroundStyle(Theme.text3)
                }
            }
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.canvas)
    }
}
#endif
