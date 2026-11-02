import SwiftUI
import BudKit

// Thin cross-platform host for the BudKit prototype. BudRootView (the orbit canvas, trail, and
// add-bud flow) lives in the BudKit package and is shared verbatim by every platform target; this
// app only provides the @main entry point and the window. On tvOS the package offers BudTVView
// instead: the same orbit canvas driven by the remote's focus, plus capture and completion.
@main
struct BudApp: App {
    var body: some Scene {
        WindowGroup {
            #if os(tvOS)
            BudTVView()
            #else
            BudRootView()
            #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 760)
        #endif
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
