import Foundation
import BudKit
#if canImport(UIKit)
import UIKit
#endif

/// Where the app's store comes from: the vault folder on disk, through the Rust core.
@MainActor
enum Launch {
    static var platform: VaultPlatform {
        #if os(macOS)
        return .macOS
        #elseif os(tvOS)
        return .tvOS
        #else
        return .iOS
        #endif
    }

    /// The name this device's system gives it, sent to its peers.
    static var deviceName: String? {
        #if os(macOS)
        return Host.current().localizedName
        #else
        return UIDevice.current.name
        #endif
    }

    /// The store over this device's vault, with a node that pairs and syncs it. The first launch
    /// on a device that kept its buds in the old JSON file plants them in the empty vault and sets
    /// the file aside. A vault that will not open leaves the app on the JSON file, as before; a
    /// node that will not start leaves the vault unsynced, alone in Settings.
    static func store() -> BudStore {
        let paths = VaultPaths(platform: platform, base: URL(fileURLWithPath: NSHomeDirectory()))
        guard let vault = try? RustVault(paths: paths) else { return BudStore() }
        if let file = BudStore.defaultFile, let tree = old(file), (try? vault.core.snapshot().isEmpty) == true {
            do {
                try vault.plant(tree.records())
                try FileManager.default.moveItem(at: file, to: file.deletingPathExtension().appendingPathExtension("imported.json"))
            } catch {
                NSLog("Bud: the old buds did not move into the vault: \(error)")
            }
        }
        let launchedForPictures = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-bud") }
        if !launchedForPictures {
            do {
                let peers = try RustPeers(vault: vault, kind: BudStore.platformSource, name: deviceName)
                DeviceStore.shared = DeviceStore(peers: peers)
            } catch {
                NSLog("Bud: the sync node did not start: \(error)")
            }
        }
        return BudStore(vault: vault)
    }

    private static func old(_ file: URL) -> Tree? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Tree.self, from: data)
    }
}
