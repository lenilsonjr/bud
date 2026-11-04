import Foundation
import BudKit
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import SystemConfiguration
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
        return SCDynamicStoreCopyComputerName(nil, nil) as String?
        #else
        return UIDevice.current.name
        #endif
    }

    /// The store over this device's vault, with a node that pairs and syncs it. The vault opens
    /// at once; bringing in the old JSON file and starting the node happen off the main thread,
    /// and the store reloads and Settings follows the node when they are done. A vault that will
    /// not open leaves the app on the JSON file, as before; a node that will not start leaves the
    /// vault unsynced, alone in Settings.
    static func store() -> BudStore {
        let paths = VaultPaths(platform: platform, base: URL(fileURLWithPath: NSHomeDirectory()))
        guard let vault = try? RustVault(paths: paths) else { return BudStore() }
        let store = BudStore(vault: vault)
        let devices = store.devices
        let platform = platform
        let kind = BudStore.platformSource
        let name = deviceName
        let launchedForPictures = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-bud") }
        Task.detached(priority: .userInitiated) {
            if bringOldBuds(into: vault, platform: platform) { await store.reload() }
            guard !launchedForPictures else { return }
            do {
                let peers = try RustPeers(vault: vault, kind: kind, name: name)
                await devices.use(peers)
            } catch {
                NSLog("Bud: the sync node did not start: \(error)")
            }
        }
        return store
    }

    /// Plants the buds a device kept in the old JSON file into its empty vault, once, and sets
    /// the file aside. The Apple TV's vault is a cache its peers fill, and a file that only holds
    /// the sample world is left out: two devices planting it would collide when they pair.
    /// Returns whether anything was planted.
    nonisolated static func bringOldBuds(into vault: RustVault, platform: VaultPlatform) -> Bool {
        guard platform != .tvOS, let file = BudStore.defaultFile, let data = try? Data(contentsOf: file),
              let tree = try? JSONDecoder().decode(Tree.self, from: data),
              (try? vault.core.snapshot().isEmpty) == true
        else { return false }
        let sample = Set(Tree.seed().buds.map(\.text))
        let planted = Set(tree.buds.map(\.text)) != sample
        if planted { vault.plant(tree.records()) }
        do {
            try FileManager.default.moveItem(at: file, to: file.deletingPathExtension().appendingPathExtension("imported.json"))
        } catch {
            NSLog("Bud: the old buds file stays where it was: \(error)")
        }
        return planted
    }
}
