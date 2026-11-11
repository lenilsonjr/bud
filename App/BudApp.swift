import SwiftUI
import BudKit

// Thin cross-platform host for the BudKit prototype. BudRootView (the orbit canvas, trail, and
// add-bud flow) lives in the BudKit package and is shared verbatim by every platform target; this
// app only provides the @main entry point and the window. On tvOS the package offers BudTVView
// instead: the same orbit canvas driven by the remote's focus, plus capture and completion.
@main
struct BudApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(BudAppDelegate.self) private var delegate
    #endif
    /// One store for every window, over the vault on disk.
    @StateObject private var store = Launch.store()

    var body: some Scene {
        WindowGroup {
            #if os(tvOS)
            BudTVView(store: store)
            #elseif os(macOS)
            // The desktop palette searches the window's store and goes through it.
            BudRootView(store: store, listensForCaptures: !Launch.forPictures)
                .onAppear { delegate.attach(store) }
            #else
            BudRootView(store: store, listensForCaptures: !Launch.forPictures)
            #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 760)
        .commands { BudCommands(store: store) }
        #endif
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
