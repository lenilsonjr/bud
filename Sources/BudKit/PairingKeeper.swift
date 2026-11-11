import Foundation

/// Keeps this device's pairing where a cleared cache cannot take it. The Apple TV holds its
/// vault and index under Caches; with the pairing kept apart, a launch that finds them gone
/// starts as the same device with the same peers and fetches the vault back from them.
///
/// The Keychain outlives the app, so the copy carries the id of the install that kept it, held
/// in the app's own defaults, which a Caches clear leaves and deleting the app takes. A copy from
/// another install, or one with no install id, is never brought back: an app deleted and
/// installed again starts unpaired.
public struct PairingKeeper: Sendable {
    /// The account the pairing is kept under.
    static let account = "pairing"
    /// The Keychain service on a device.
    public static let service = "bud.pairing"
    /// Where the install's id lives in the defaults.
    static let installKey = "pairing.install"

    private let store: TokenStore
    /// What the Keychain holds, once read.
    private let held = Held()
    /// This install's id, made the first time.
    let install: String

    public init(store: TokenStore, defaults: UserDefaults = .standard) {
        self.store = store
        if let known = defaults.string(forKey: Self.installKey) {
            install = known
        } else {
            install = UUID().uuidString
            defaults.set(install, forKey: Self.installKey)
        }
    }

    /// The pairing this install kept last, or nil when there is none, it came from another
    /// install, or it was damaged.
    public var kept: Data? {
        guard let text = token else { return nil }
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == install else { return nil }
        return Data(base64Encoded: parts[1])
    }

    /// Lets a copy go that this install cannot use: another install's, or a damaged one. Called
    /// at launch, before anything reads the copy.
    public func dropForeign() {
        guard token != nil, kept == nil else { return }
        write(nil)
    }

    /// Keeps the vault's pairing as it is now. Nil, a vault with its node key and no peer, is an
    /// unpaired device, and the copy goes: a restore that failed starts no node and so makes no
    /// key, and a vault with a key never takes a kept copy. Writes only when it changed, so
    /// calling it often costs a comparison. False when the write failed; the copy before stays.
    @discardableResult
    public func keep(_ pairing: Data?) -> Bool {
        guard let pairing else { return forget() }
        guard pairing != kept else { return true }
        return write(install + ":" + pairing.base64EncodedString())
    }

    /// Lets the kept copy go, whatever it holds, damaged or not. False when it could not.
    @discardableResult
    public func forget() -> Bool {
        guard token != nil else { return true }
        return write(nil)
    }

    /// The keeper a launch with `arguments` uses, made by `make` only when one is wanted: on the
    /// Apple TV, whose vault is a cache, and never on a tour or for pictures, which start no node
    /// and leave the Keychain and the install id alone. A copy this install cannot use goes here,
    /// before anything reads it.
    public static func forLaunch(
        platform: VaultPlatform, arguments: [String], make: () -> PairingKeeper
    ) -> PairingKeeper? {
        guard platform == .tvOS, !LaunchArguments.isTour(arguments) else { return nil }
        let keeper = make()
        keeper.dropForeign()
        return keeper
    }

    /// The text kept in the Keychain. The keeper is its only writer while the app runs, so it
    /// reads the Keychain once and remembers what it wrote since.
    private var token: String? {
        held.text { store.token(for: Self.account) }
    }

    /// Writes `text` to the Keychain, or deletes the copy with nil. A write that failed leaves
    /// the Keychain unknown, so the next look reads it again.
    @discardableResult
    private func write(_ text: String?) -> Bool {
        let written = store.set(text, for: Self.account)
        held.note(written ? .some(text) : nil)
        return written
    }
}

/// What a launch was started for, read from its arguments.
public enum LaunchArguments {
    /// Whether a launch with these arguments is a tour or hosts pictures: every argument that
    /// starts one begins with "-bud". Such a launch starts no node and leaves the kept pairing
    /// alone.
    public static func isTour(_ arguments: [String]) -> Bool {
        arguments.contains { $0.hasPrefix("-bud") }
    }
}

/// The Keychain text a keeper read or wrote last, shared by its copies; nil until known.
private final class Held: @unchecked Sendable {
    private let lock = NSLock()
    private var known: String??

    /// The text, read with `read` the first time and remembered after.
    func text(_ read: () -> String?) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let known { return known }
        let text = read()
        known = .some(text)
        return text
    }

    /// Remembers `text`, or forgets what was known with nil, so the next look reads again.
    func note(_ text: String??) {
        lock.lock(); defer { lock.unlock() }
        known = text
    }
}

/// Keeps the pairing up to date, one step at a time on a queue of its own: each step reads the
/// vault's pairing and writes it, so an older read never lands after a newer one, and the read,
/// which waits on the vault, stays off the concurrency pool.
public actor PairingSync {
    private let keeper: PairingKeeper
    private let read: @Sendable () throws -> Data?
    private let queue = DispatchQueue(label: "bud.pairing", qos: .utility)
    private var timer: Task<Void, Never>?

    /// `read` takes the vault's pairing as it is now; it may wait on the vault.
    public init(keeper: PairingKeeper, read: @escaping @Sendable () throws -> Data?) {
        self.keeper = keeper
        self.read = read
    }

    deinit { timer?.cancel() }

    /// Reads the pairing and keeps it; a vault that reads as unpaired lets the copy go. A pairing
    /// that cannot be read leaves the kept one alone.
    public func keep() async {
        await run { [keeper, read] in
            do {
                if !keeper.keep(try read()) { NSLog("Bud: the Keychain did not take the pairing") }
            } catch {
                NSLog("Bud: the pairing was not kept: \(error)")
            }
        }
    }

    /// Lets the kept pairing go at once, when the last other device was removed, but only when
    /// the vault still reads as unpaired: a forget that runs after the device paired again leaves
    /// the new copy, so the order of the steps does not matter. `keep` would find the same.
    public func forget() async {
        await run { [keeper, read] in
            // A vault that cannot be read is no sign the device is unpaired.
            guard let unpaired = try? read() == nil, unpaired else { return }
            if !keeper.forget() { NSLog("Bud: the Keychain did not let the pairing go") }
        }
    }

    /// Queues a step behind the ones before. The step joins the queue before this suspends, so
    /// steps run in the order they were asked for.
    private func run(_ step: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async {
                step()
                done.resume()
            }
        }
    }

    /// Keeps it again every `interval` seconds, for changes that come with no event, such as a
    /// key another device rotated, until `stop`.
    public func start(every interval: TimeInterval) {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.keep()
            }
        }
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }
}
