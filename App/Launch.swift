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
    ///
    /// On the Apple TV the vault is a cache. When the vault takes the pairing kept in the
    /// Keychain (it has no node key and no peers of its own, as after the system cleared Caches,
    /// or a restore was cut short), the pairing comes back and the cards wait for the first fetch
    /// from the peers. The index is never deleted here.
    static func store() -> BudStore {
        let paths = VaultPaths(platform: platform, base: URL(fileURLWithPath: NSHomeDirectory()))
        let keeper = pairingKeeper
        let onTour = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-bud") }
        // Tours and pictures start no node, so nothing would end a wait, and leave the kept
        // pairing alone. A copy this build cannot read is no pairing either.
        let kept = onTour ? nil : keeper?.kept.flatMap { pairingIsUsable(pairing: $0) ? $0 : nil }
        // An index gone with buds left in the folder: they would come back as new buds beside
        // the peers' own, so they go before the first scan, when the pairing will come back.
        if kept != nil, paths.fetchesFromPeer() { paths.emptyVaultFolder() }
        guard let vault = try? RustVault(paths: paths) else {
            let store = BudStore()
            if !forPictures { listenForCaptures(into: store) }
            return store
        }
        // Decided by the vault's state, one small read of the index, so the wait is up before the
        // first card; the restore itself runs off the main thread.
        let restoring = kept.map { (try? vault.core.takesPairing(pairing: $0)) == true } == true
        let store = BudStore(vault: vault)
        if restoring { store.devices.awaitLaunchFetch() }
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
        Task.detached(priority: .userInitiated) {
            if bringOldBuds(into: vault, platform: platform) { await store.reload() }
            // After the old file: it plants only into an empty vault, and a capture landing
            // first would keep it out. Lines captured meanwhile wait in the relay.
            await listenForCaptures(into: store)
            guard !onTour else { return }
            var restored = restoring
            if restoring, let kept {
                do {
                    if !(try vault.core.restorePairing(pairing: kept)) {
                        restored = false
                        await devices.endLaunchFetch()
                    }
                } catch {
                    // A restore that failed once would likely fail on every launch and leave the TV
                    // with no node at all. The kept copy goes, and the TV starts unpaired, ready to
                    // be invited again.
                    NSLog("Bud: the kept pairing did not come back: \(error)")
                    _ = keeper?.forget()
                    restored = false
                    await devices.endLaunchFetch()
                }
            }
            do {
                let peers = try RustPeers(vault: vault, kind: kind, name: name)
                await devices.use(peers)
                if let keeper { await keepPairing(of: vault, in: keeper, following: devices) }
                if restored {
                    // The node dials its peers one after another, each up to the core's session
                    // timeout: the wait gives them all that, and one session more.
                    await devices.startLaunchFetchPatience(sessionTimeout: TimeInterval(sessionTimeoutSeconds()))
                    // A cleared TV asks its peers at once rather than on the node's next round.
                    await devices.syncNow()
                }
            } catch {
                if restored { await devices.endLaunchFetch() }
                NSLog("Bud: the sync node did not start: \(error)")
            }
        }
        return store
    }

    /// Captures made outside a window land in the store every window shows while the app runs,
    /// whichever windows come and go.
    private static func listenForCaptures(into store: BudStore) {
        #if !os(tvOS)
        CaptureRelay.shared.listen { line in store.capture(line) }
        #endif
    }

    /// Where the pairing is kept apart from the vault: only on the Apple TV, whose vault and
    /// index the system may clear.
    private static var pairingKeeper: PairingKeeper? {
        #if os(tvOS)
        let keeper = PairingKeeper(store: KeychainTokens(service: PairingKeeper.service))
        // A copy kept by an install of the app that was deleted goes, rather than rejoining.
        keeper.dropForeign()
        return keeper
        #else
        return nil
        #endif
    }

    /// The pairing kept up to date for as long as the app runs.
    private static var pairingSync: PairingSync?

    /// Keeps the pairing up to date while the app runs: now, after every change the devices or
    /// the node tell of, when the app leaves the foreground, and every few minutes besides.
    /// One step at a time, so an older read never lands after a newer one. Nothing waits for
    /// the first step: the launch fetch goes on beside it.
    private static func keepPairing(of vault: RustVault, in keeper: PairingKeeper, following devices: DeviceStore) async {
        let sync = PairingSync(keeper: keeper) { try vault.core.pairing() }
        pairingSync = sync
        devices.onPairingChanged = { Task { await sync.keep() } }
        devices.onUnpaired = { Task { await sync.forget() } }
        Task { await sync.keep() }
        await sync.start(every: 5 * 60)
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
