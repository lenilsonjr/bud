import Foundation

/// Keeps this device's pairing where a cleared cache cannot take it. The Apple TV holds its
/// vault and index under Caches; with the pairing kept apart, a launch that finds them gone
/// starts as the same device with the same peers and fetches the vault back from them.
public struct PairingKeeper: Sendable {
    /// The account the pairing is kept under.
    static let account = "pairing"
    /// The Keychain service on a device.
    public static let service = "bud.pairing"

    private let store: TokenStore

    public init(store: TokenStore) {
        self.store = store
    }

    /// The pairing kept last, or nil when there is none or it was damaged.
    public var kept: Data? {
        store.token(for: Self.account).flatMap { Data(base64Encoded: $0) }
    }

    /// Keeps the vault's pairing as it is now. Nil, a vault with no peer, keeps the copy there
    /// is: a restore that failed reads the same as no pairing, and only `forget` lets it go.
    /// Writes only when it changed, so calling it often costs a read. False when the write
    /// failed; the copy before stays.
    @discardableResult
    public func keep(_ pairing: Data?) -> Bool {
        guard let pairing, pairing != kept else { return true }
        return store.set(pairing.base64EncodedString(), for: Self.account)
    }

    /// Lets the kept pairing go: this device has no other left. False when it could not.
    @discardableResult
    public func forget() -> Bool {
        guard kept != nil else { return true }
        return store.set(nil, for: Self.account)
    }
}

/// Keeps the pairing up to date, one step at a time: each step reads the vault's pairing and
/// writes it, so an older read never lands after a newer one.
public actor PairingSync {
    private let keeper: PairingKeeper
    private let read: @Sendable () throws -> Data?
    private var timer: Task<Void, Never>?

    /// `read` takes the vault's pairing as it is now; it may wait on the vault.
    public init(keeper: PairingKeeper, read: @escaping @Sendable () throws -> Data?) {
        self.keeper = keeper
        self.read = read
    }

    deinit { timer?.cancel() }

    /// Reads the pairing and keeps it. A pairing that cannot be read leaves the kept one alone.
    public func keep() {
        do {
            if !keeper.keep(try read()) { NSLog("Bud: the Keychain did not take the pairing") }
        } catch {
            NSLog("Bud: the pairing was not kept: \(error)")
        }
    }

    /// Lets the kept pairing go, after the last other device was removed.
    public func forget() {
        if !keeper.forget() { NSLog("Bud: the Keychain did not let the pairing go") }
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
