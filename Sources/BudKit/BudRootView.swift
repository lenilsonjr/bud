#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The whole app: the bar across the top, the canvas or the files below it.
public struct BudRootView: View {
    @StateObject private var store: BudStore
    @ObservedObject private var flags = Flags.shared
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
            TopBar(store: store, onAdd: { store.modal = .capture }, onSearch: { searching = true })
            surface
                .overlay(alignment: .bottom) {
                    ToastView(center: store.toasts)
                        .padding(12)
                    .animation(.spring(duration: 0.4, bounce: 0.2), value: store.toasts.current?.id)
                }
        }
        .overlay { if searching { palette } }
        .overlay { ModalHost(store: store) }
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
        .preferredColorScheme(flags.appearance.colorScheme)
        .environmentObject(flags)
        .onAppear { CaptureRelay.shared.listen { line in store.capture(line) } }
        .onDisappear { CaptureRelay.shared.stopListening() }
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
}
#endif
