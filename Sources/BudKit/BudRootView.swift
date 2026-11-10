#if canImport(SwiftUI) && !os(tvOS)
import Combine
import SwiftUI

/// The whole app: the bar across the top, the canvas or the files below it.
public struct BudRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: BudStore
    @ObservedObject private var flags = Flags.shared
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compact: Bool { sizeClass == .compact }
    #else
    @Environment(\.compact) private var compact
    #endif

    @MainActor public init(fileURL: URL? = BudStore.defaultFile) {
        _store = StateObject(wrappedValue: BudStore(fileURL: fileURL))
    }

    /// A store the caller already holds: the app's, over the vault on disk, or one for pictures.
    @MainActor public init(store: BudStore) {
        _store = StateObject(wrappedValue: store)
    }

    public var body: some View {
        VStack(spacing: 0) {
            TopBar(store: store, onAdd: { store.perform(.capture) }, onSearch: { store.perform(.goAnywhere) })
            surface
        }
        .overlay { if store.searching && !compact { palette } }
        .sheet(isPresented: Binding(get: { store.searching && compact }, set: { store.searching = $0 })) { paletteSheet }
        .overlay { ModalHost(store: store) }
        // Above the modal too, so a toast from a dialog shows while Settings still covers the window.
        .overlay(alignment: .bottom) {
            ToastView(center: store.toasts)
                .padding(12)
                .animation(.spring(duration: 0.4, bounce: 0.2), value: store.toasts.current?.id)
        }
        .background(Theme.window.ignoresSafeArea())
        .background {
            // The window's keys, drawn nowhere: Go anywhere, and the switch between the surfaces.
            Group {
                Button("") { store.perform(.goAnywhere) }
                    .keyboardShortcut(Keys.shortcut(.goAnywhere))
                Button("") { store.perform(.canvas) }
                    .keyboardShortcut(Keys.shortcut(.canvas))
                Button("") { store.perform(.files) }
                    .keyboardShortcut(Keys.shortcut(.files))
            }
            .opacity(0)
        }
        .textRole(.body)
        .foregroundStyle(Theme.text)
        .tint(Theme.leaf)
        .preferredColorScheme(flags.appearance.colorScheme)
        .environmentObject(flags)
        .environment(\.compact, compact)
        .environment(\.goAnywhere, { store.perform(.goAnywhere) })
        .onAppear { CaptureRelay.shared.listen { line in store.capture(line) } }
        .onDisappear { CaptureRelay.shared.stopListening() }
        .onReceive(NotificationCenter.default.publisher(for: BudStore.freshStartRequested)) { note in
            store.freshStart(sample: note.userInfo?["sample"] as? Bool ?? false)
        }
        // Today and Overdue move at midnight, edits or not.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            store.refreshLens()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refreshLens() }
        }
    }

    @ViewBuilder private var surface: some View {
        switch store.surface {
        case .canvas:
            OrbitCanvas(store: store)
        case .files:
            FilesView(store: store)
        }
    }

    /// Go anywhere on a phone: a sheet from the bottom with the keyboard up, half the screen or
    /// the whole of it, as the third iPhone frame; a pull down dismisses it.
    private var paletteSheet: some View {
        CommandPalette(store: store, inSheet: true) { store.searching = false }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Theme.raised)
    }

    /// Go anywhere over the whole view; a click on the dim closes it.
    private var palette: some View {
        ZStack(alignment: .top) {
            Theme.shadowStrong
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { store.searching = false }
            CommandPalette(store: store) { store.searching = false }
                .padding(.horizontal, compact ? 12 : 0)
                .padding(.top, compact ? 8 : 72)
        }
        .transition(.opacity)
    }
}
#endif
