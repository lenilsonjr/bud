#if canImport(SwiftUI)
import SwiftUI
import BudKit

struct BudMacApp: App {
    var body: some Scene {
        WindowGroup("Bud") {
            BudRootView()
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}

BudMacApp.main()
#else
print("BudMac needs SwiftUI. On a Mac, run: swift run BudMac")
#endif
