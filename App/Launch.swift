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
        let arguments = ProcessInfo.processInfo.arguments
        let onTour = LaunchArguments.isTour(arguments)
        // Only on the Apple TV, whose vault and index the system may clear. Tours and pictures
        // start no node, so nothing would end a wait, and get no keeper: the Keychain copy and
        // the install id stay as they are.
        let keeper = PairingKeeper.forLaunch(platform: platform, arguments: arguments) {
            PairingKeeper(store: KeychainTokens(service: PairingKeeper.service))
        }
        // A copy this build cannot read is no pairing either.
        let kept = keeper?.kept.flatMap { pairingIsUsable(pairing: $0) ? $0 : nil }
        // An index gone with buds left in the folder: they would come back as new buds beside
        // the peers' own, so they go before the first scan, when the pairing will come back.
        if kept != nil, paths.fetchesFromPeer(nodeKey: nodeKeyFileName()) { paths.emptyVaultFolder() }
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
            if await bringOldBuds(into: vault, platform: platform) { await store.reload() }
            // After the old file, so its buds come in before the first capture. Lines captured
            // meanwhile wait in the relay.
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

    /// The pairing kept up to date for as long as the app runs.
    private static var pairingSync: PairingSync?

    /// Keeps the pairing up to date while the app runs: now, after every change the devices or
    /// the node tell of, when the app leaves the foreground, and every few minutes besides.
    /// One step at a time, so an older read never lands after a newer one. Nothing waits for
    /// the first step: the launch fetch goes on beside it.
    private static func keepPairing(of vault: RustVault, in keeper: PairingKeeper, following devices: DeviceStore) async {
        let sync = PairingSync(keeper: keeper) { try vault.core.pairing() }
        pairingSync = sync
        devices.onPairingChanged = { keep(sync) }
        devices.onUnpaired = { Task { await sync.forget() } }
        Task { await sync.keep() }
        await sync.start(every: 5 * 60)
    }

    /// Keeps the pairing now. On the Apple TV the step runs under a background task, so a keep
    /// asked for on the way into the background finishes before the app is suspended.
    private static func keep(_ sync: PairingSync) {
        #if os(tvOS)
        let task = BackgroundTask(named: "Keep the pairing")
        Task {
            await sync.keep()
            task.end()
        }
        #else
        Task { await sync.keep() }
        #endif
    }

    /// Plants the buds a device kept in the old JSON file into its vault, once, and sets the file
    /// aside; `OldBuds` decides what comes in. Returns whether anything was planted.
    nonisolated static func bringOldBuds(into vault: RustVault, platform: VaultPlatform) async -> Bool {
        guard let file = BudStore.defaultFile else { return false }
        return await OldBuds.bring(from: file, platform: platform) { _ = vault.plant($0) }
    }
}

#if os(tvOS)
/// Time the system grants the app to finish a step after it leaves the foreground, ended once
/// the step is done or the time runs out, whichever comes first.
@MainActor
private final class BackgroundTask {
    private var id = UIBackgroundTaskIdentifier.invalid

    init(named name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
#endif
