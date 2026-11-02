#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The whole app: the bar across the top, the canvas or the files below it, a hint at the bottom.
public struct BudRootView: View {
    @StateObject private var store: BudStore
    @State private var adding: AddTarget? = nil
    @State private var searching = false

    @MainActor public init(fileURL: URL? = BudStore.defaultFile) {
        _store = StateObject(wrappedValue: BudStore(fileURL: fileURL))
    }

    /// For previews and pictures: a store the caller already holds.
    @MainActor init(store: BudStore) {
        _store = StateObject(wrappedValue: store)
    }

    public var body: some View {
        VStack(spacing: 0) {
            TopBar(store: store, onAdd: { adding = .capture }, onSearch: { searching = true })
            surface
                .overlay(alignment: .bottom) {
                    VStack(spacing: 10) {
                        ToastView(center: store.toasts)
                        hint
                    }
                    .animation(.spring(duration: 0.4, bounce: 0.2), value: store.toasts.current?.id)
                }
        }
        .overlay { if searching { palette } }
        .background(Theme.window.ignoresSafeArea())
        .background {
            // ⌘K from anywhere in the window, drawn nowhere.
            Button("") { searching = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
        }
        .textRole(.body)
        .foregroundStyle(Theme.text)
        .tint(Theme.leaf)
        .sheet(item: $adding) { target in AddSheet(store: store, mode: target.mode) }
    }

    @ViewBuilder private var surface: some View {
        switch store.surface {
        case .canvas:
            OrbitCanvas(store: store)
        case .files:
            FilesView(store: store)
        }
    }

    /// Go anywhere over the whole view; a click on the dim closes it.
    private var palette: some View {
        ZStack(alignment: .top) {
            Theme.shadowStrong
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { searching = false }
            CommandPalette(store: store) { searching = false }
                .padding(.top, 72)
        }
        .transition(.opacity)
    }

    private var hint: some View {
        Text("Drag or scroll to move · pinch to zoom · tap a card with children to center it · tap a leaf or press Space to open it · N adds under the lit card · ⌘K goes anywhere · Esc steps out")
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
