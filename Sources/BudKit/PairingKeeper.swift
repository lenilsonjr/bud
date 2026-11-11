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
        guard let text = store.token(for: Self.account) else { return nil }
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == install else { return nil }
        return Data(base64Encoded: parts[1])
    }

    /// Lets a copy go that this install cannot use: another install's, or a damaged one. Called
    /// at launch, before anything reads the copy.
    public func dropForeign() {
        guard store.token(for: Self.account) != nil, kept == nil else { return }
        store.set(nil, for: Self.account)
    }

    /// Keeps the vault's pairing as it is now. Nil, a vault with no peer, keeps the copy there
    /// is: a restore that failed reads the same as no pairing, and only `forget` lets it go.
    /// Writes only when it changed, so calling it often costs a read. False when the write
    /// failed; the copy before stays.
    @discardableResult
    public func keep(_ pairing: Data?) -> Bool {
        guard let pairing, pairing != kept else { return true }
        return store.set(install + ":" + pairing.base64EncodedString(), for: Self.account)
    }

    /// Lets the kept copy go, whatever it holds, damaged or not. False when it could not.
    @discardableResult
    public func forget() -> Bool {
        guard store.token(for: Self.account) != nil else { return true }
        return store.set(nil, for: Self.account)
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

    /// Reads the pairing and keeps it. A pairing that cannot be read leaves the kept one alone.
    public func keep() async {
        await run { [keeper, read] in
            do {
                if !keeper.keep(try read()) { NSLog("Bud: the Keychain did not take the pairing") }
            } catch {
                NSLog("Bud: the pairing was not kept: \(error)")
            }
        }
    }

    /// Lets the kept pairing go, but only when the vault still reads as unpaired: a forget that
    /// runs after the device paired again leaves the new copy, so the order of the steps does
    /// not matter.
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
