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

    /// Whether the app was launched to host pictures.
    static let forPictures = ProcessInfo.processInfo.arguments.contains(BudStore.picturesArgument)

    /// The store over this device's vault, with a node that pairs and syncs it. The vault opens
    /// at once; bringing in the old JSON file and starting the node happen off the main thread,
    /// and the store reloads and Settings follows the node when they are done. A vault that will
    /// not open leaves the app on the JSON file, as before; a node that will not start leaves the
    /// vault unsynced, alone in Settings. A tour starts no node; an app launched for pictures
    /// opens its vault and does none of the rest: no node, no source, no trigger, no old file.
    static func store() -> BudStore {
        let paths = VaultPaths(platform: platform, base: URL(fileURLWithPath: NSHomeDirectory()))
        guard let vault = try? RustVault(paths: paths) else { return BudStore() }
        let store = BudStore(vault: vault)
        #if !os(tvOS)
        // The TV shows no soil, only the source rows of buds planted elsewhere, and keeps a copy
        // of the vault that fires no trigger of its own. Pictures poll no source either.
        if !forPictures {
            store.follow(SourceStore.shared)
            store.startTriggers()
        }
        #endif
        let devices = store.devices
        let platform = platform
        let kind = BudStore.platformSource
        let name = deviceName
        guard !forPictures else { return store }
        let onTour = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-bud") }
        Task.detached(priority: .userInitiated) {
            if bringOldBuds(into: vault, platform: platform) { await store.reload() }
            guard !onTour else { return }
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
    /// the untouched sample world is left out: two devices planting it would collide when they
    /// pair. A sample that was ticked, pinned, written in, moved or scheduled is the person's own
    /// and is planted.
    /// Returns whether anything was planted.
    nonisolated static func bringOldBuds(into vault: RustVault, platform: VaultPlatform) -> Bool {
        guard platform != .tvOS, let file = BudStore.defaultFile, let data = try? Data(contentsOf: file),
              let tree = try? JSONDecoder().decode(Tree.self, from: data),
              (try? vault.core.snapshot().isEmpty) == true
        else { return false }
        let planted = shape(of: tree) != shape(of: Tree.seed())
        if planted { vault.plant(tree.records()) }
        do {
            try FileManager.default.moveItem(at: file, to: file.deletingPathExtension().appendingPathExtension("imported.json"))
        } catch {
            NSLog("Bud: the old buds file stays where it was: \(error)")
        }
        return planted
    }

    /// What tells a person's buds from the untouched sample world: each bud's title, where it
    /// is (its place and the title above it), state, pin, body, and whether it has a day or a
    /// due date. The dates themselves are left out, since the sample's are set from the day it
    /// was made.
    private nonisolated static func shape(of tree: Tree) -> Set<String> {
        let records = tree.records().filter { $0.place != .trash }
        let titles = Dictionary(records.map { ($0.path, $0.title) }, uniquingKeysWith: { first, _ in first })
        return Set(records.map { record in
            [
                record.title, record.place.rawValue, record.parent.flatMap { titles[$0] } ?? "",
                record.state?.rawValue ?? "note", String(record.pinned), record.body,
                String(record.when != nil), String(record.due != nil),
            ].joined(separator: "\u{1F}")
        })
    }
}
