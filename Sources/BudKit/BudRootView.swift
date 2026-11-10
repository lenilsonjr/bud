#if canImport(SwiftUI) && !os(tvOS)
import Combine
import SwiftUI

/// The whole app: the bar across the top, the view it switches to below it.
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
        .overlay(alignment: .bottomTrailing) { helpButton }
        .overlay { ModalHost(store: store) }
        // Above the modal too, so a toast from a dialog shows while Settings still covers the window.
        .overlay(alignment: .bottom) {
            ToastView(center: store.toasts)
                .padding(12)
                .animation(.spring(duration: 0.4, bounce: 0.2), value: store.toasts.current?.id)
        }
        .background(Theme.window.ignoresSafeArea())
        .background {
            // The window's keys, drawn nowhere: Go anywhere, the switch between the views, and
            // the shortcuts sheet. They lose their keys while the sheet records one, so the
            // recorder hears it.
            Group {
                Button("") { store.perform(.goAnywhere) }
                    .keyboardShortcut(windowKey(.goAnywhere))
                ForEach(Surface.allCases, id: \.self) { view in
                    Button("") { store.perform(view.command) }
                        .keyboardShortcut(windowKey(view.command))
                }
                Button("") { store.perform(.shortcuts) }
                    .keyboardShortcut(windowKey(.shortcuts))
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

    /// A window key's shortcut, or none while the shortcuts sheet records a key.
    private func windowKey(_ id: Command.ID) -> KeyboardShortcut? {
        Keys.layout.recording == nil ? Keys.shortcut(id) : nil
    }

    /// The help button at the bottom right of the window, on the Mac only: the sheet under it
    /// still opens on its key anywhere a keyboard is. It goes while Go anywhere is up, since the
    /// palette's dim would leave it clickable.
    @ViewBuilder private var helpButton: some View {
        #if os(macOS)
        if !store.searching {
            HelpButton { store.perform(.shortcuts) }
                .padding(16)
        }
        #endif
    }

    @ViewBuilder private var surface: some View {
        switch store.surface {
        case .canvas:
            OrbitCanvas(store: store)
        case .files:
            FilesView(store: store)
        case .board:
            BoardView(store: store)
        case .calendar:
            CalendarView(store: store)
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
