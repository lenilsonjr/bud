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
            FilesView(store: store)
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
#endif
