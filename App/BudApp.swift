import SwiftUI
import BudKit

// Thin cross-platform host for the BudKit prototype. BudRootView (the orbit canvas, trail, and
// add-bud flow) lives in the BudKit package and is shared verbatim by every platform target; this
// app only provides the @main entry point and the window. tvOS / watchOS targets will add their own
// entry points here beside this one when BudKit grows those platforms.
@main
struct BudApp: App {
    var body: some Scene {
        WindowGroup {
            BudRootView()
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 760)
        #endif
    }
}
