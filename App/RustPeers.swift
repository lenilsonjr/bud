import Foundation
import BudKit

/// BudKit's `Peers` over the Rust core's node: pairing, the devices, and the sync it runs every few
/// seconds on its own. A bare name here is the core's, as in `RustVault`.
final class RustPeers: BudKit.Peers, @unchecked Sendable {
    private let vault: Vault
    private let kind: String
    private let name: String?
    private let lock = NSLock()
    private var node: PeerNode
    /// A relay change could start no node, and `node` is the stopped one.
    private var stopped = false
    private let hub = Hub()

    /// Starts a node for the vault with the relay last chosen, telling peers what this device is.
    init(vault: RustVault, kind: String, name: String?) throws {
        self.vault = vault.core
        self.kind = kind
        self.name = name
        node = try startNodeAs(vault: vault.core, relay: Self.core(Self.storedRelay), kind: kind, name: name)
        try node.listen(listener: hub)
    }

    /// The node, started again on the setting last chosen when a relay change left none
    /// running, so the next call tries once more instead of finding it closed until relaunch.
    /// Starting waits on the network: call it off the cooperative pool.
    private func live() throws -> PeerNode {
        lock.lock()
        defer { lock.unlock() }
        if stopped {
            let fresh = try startNodeAs(vault: vault, relay: Self.core(Self.storedRelay), kind: kind, name: name)
            try? fresh.listen(listener: hub)
            node = fresh
            stopped = false
        }
        return node
    }

    /// Runs a call into the core off the cooperative pool: a sync waits on the network.
    private func off<T>(_ call: @escaping @Sendable (PeerNode) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { done in
            DispatchQueue.global(qos: .userInitiated).async {
                done.resume(with: Result { try call(self.live()) })
            }
        }
    }

    func devices() async throws -> [Device] {
        let (me, peers) = try await off { try ($0.id(), $0.peers()) }
        let this = Device(id: me, isThisDevice: true, reach: .local, name: name, kind: DeviceKind(rawValue: kind))
        return [this] + peers.map(Self.device)
    }

    func ticket(withAddresses: Bool) async throws -> Ticket {
        let (text, qr) = try await off { node -> (String, [[Bool]]) in
            let text = try node.ticket(withAddresses: withAddresses)
            return (text, try node.ticketQr(withAddresses: withAddresses))
        }
        return Ticket(text: text, qr: qr, madeAt: Date())
    }

    func accept(_ text: String) async throws -> Device {
        do {
            return Self.device(try await off { try $0.acceptTicket(ticket: text) })
        } catch {
            throw AcceptError(message: String(describing: error)) ?? .unreachable
        }
    }

    func joinRequest() async throws -> JoinRequest {
        let (code, qr) = try await off { node -> (JoinCode, [[Bool]]) in
            let code = try node.joinRequest()
            return (code, try node.joinRequestQr(code: code.code))
        }
        return JoinRequest(code: code.code, qr: qr, words: code.words, madeAt: Date())
    }

    func readRequest(_ code: String) async throws -> [String] {
        do { return try await off { try $0.readRequest(code: code) } } catch { throw RequestError(error) }
    }

    func confirmRequest(_ code: String) async throws -> Device {
        do { return Self.device(try await off { try $0.confirmRequest(code: code) }) } catch { throw RequestError(error) }
    }

    func answerJoin(keep: Bool) async throws { try await off { try $0.answerJoin(keep: keep) } }
    func remove(_ id: String) async throws { try await off { try $0.forgetPeer(id: id) } }
    func rename(_ id: String, label: String?) async throws { try await off { try $0.renamePeer(id: id, label: label) } }

    func allow(_ id: String) async throws { try await off { try $0.allowPeer(id: id) } }

    /// The core tells each peer's part as events; a rotation that fails before it is over ends
    /// with every peer missed, so the dialog never waits for good.
    func rotateKey() async throws -> AsyncStream<RotationStep> {
        let events = hub.subscribe()
        return AsyncStream { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var node: PeerNode?
                do {
                    node = try self.live()
                    _ = try node?.rotateKey()
                } catch {
                    let missed = (try? node?.peers().map(\.id)) ?? []
                    continuation.yield(.done(RotationResult(reached: 0, missed: missed, failed: true)))
                    continuation.finish()
                }
            }
            let task = Task {
                for await event in events {
                    switch event {
                    case let .keyRotation(id, confirmed, holdsKey):
                        continuation.yield(.device(id: id, reached: confirmed || holdsKey))
                    case let .rotationDone(reached, missed):
                        continuation.yield(.done(RotationResult(reached: Int(reached), missed: missed)))
                        continuation.finish()
                        return
                    default:
                        continue
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func syncNow() async throws -> BudKit.SyncSummary {
        let summary = try await off { try $0.syncNow() }
        return BudKit.SyncSummary(
            created: Int(summary.created), updated: Int(summary.updated), written: Int(summary.written),
            moved: Int(summary.moved), ops: Int(summary.ops)
        )
    }

    func state() async throws -> BudKit.SyncState {
        let state = try await off { try $0.state() }
        return BudKit.SyncState(idle: state.idle, connectedPeers: Int(state.connectedPeers), pendingChanges: Int(state.pendingChanges))
    }

    func relay() async throws -> BudKit.RelaySetting { Self.storedRelay }

    /// Starts the node again on the setting and remembers it; the pairings are the vault's and
    /// stay. The old node stops first, since both would speak for this device; a new one that
    /// will not start gives way to the old setting again, and if that will not start either,
    /// the next call tries it again.
    func setRelay(_ relay: BudKit.RelaySetting) async throws {
        try await Task.detached { [self] in
            lock.lock()
            if !stopped { node.stop() }
            lock.unlock()
            let fresh: PeerNode
            do {
                fresh = try startNodeAs(vault: vault, relay: Self.core(relay), kind: kind, name: name)
            } catch {
                do {
                    adopt(try startNodeAs(vault: vault, relay: Self.core(Self.storedRelay), kind: kind, name: name))
                } catch {
                    lock.lock()
                    stopped = true
                    lock.unlock()
                    retryLater()
                }
                throw error
            }
            adopt(fresh)
            Self.storedRelay = relay
        }.value
    }

    /// Keeps trying a stopped node every half minute, so sync comes back without a tap.
    private func retryLater() {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let stopped = self.stopped
            self.lock.unlock()
            guard stopped else { return }
            if (try? self.live()) == nil { self.retryLater() }
        }
    }

    private func adopt(_ fresh: PeerNode) {
        try? fresh.listen(listener: hub)
        lock.lock()
        node = fresh
        stopped = false
        lock.unlock()
    }

    func events() async throws -> AsyncStream<BudKit.PeerEvent> {
        let events = hub.subscribe()
        return AsyncStream { continuation in
            let task = Task { [weak self] in
                for await event in events {
                    guard let self else { break }
                    if let mapped = await self.event(event) { continuation.yield(mapped) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func event(_ event: PeerEvent) async -> BudKit.PeerEvent? {
        switch event {
        case let .ticketRedeemed(by):
            return .ticketRedeemed(by: by)
        case let .peerJoined(id):
            let known = try? await devices().first { $0.id == id }
            return .deviceJoined(known ?? Device(id: id))
        case let .joinOffered(id, kind, name, words):
            return .joinOffered(JoinOffer(id: id, kind: kind.flatMap(DeviceKind.init(rawValue:)), name: name, words: words))
        case let .fetchProgress(received, total):
            return .fetchProgress(received: Int(received), total: total.map { Int($0) })
        case let .syncFinished(summary):
            return .syncFinished(BudKit.SyncSummary(
                created: Int(summary.created), updated: Int(summary.updated), written: Int(summary.written),
                moved: Int(summary.moved), ops: Int(summary.ops)
            ))
        case .pairingChanged:
            return .pairingChanged
        case .keyRotation, .rotationDone:
            return nil
        }
    }

    // MARK: Conversions

    private static func device(_ peer: PeerRecord) -> Device {
        Device(
            id: peer.id, reach: .direct, lastSeen: peer.lastSeen.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            missed: peer.missed, name: peer.name, kind: peer.kind.flatMap(DeviceKind.init(rawValue:)), label: peer.label
        )
    }

    private static func core(_ relay: BudKit.RelaySetting) -> RelaySetting {
        switch relay {
        case .default: return .default
        case .off: return .off
        case .custom(let url): return .custom(url: url.absoluteString)
        }
    }

    private static let relayKey = "relay"

    /// The relay chosen in Settings: `default`, `off`, or a relay's URL.
    private static var storedRelay: BudKit.RelaySetting {
        get {
            switch UserDefaults.standard.string(forKey: relayKey) {
            case nil, "default": return .default
            case "off": return .off
            case let text?: return URL(string: text).map { .custom($0) } ?? .default
            }
        }
        set {
            let text: String
            switch newValue {
            case .default: text = "default"
            case .off: text = "off"
            case .custom(let url): text = url.absoluteString
            }
            UserDefaults.standard.set(text, forKey: relayKey)
        }
    }

    /// Hears the node's events on its own threads and hands each to every stream open on them.
    private final class Hub: PeerListener, @unchecked Sendable {
        private let lock = NSLock()
        private var streams: [UUID: AsyncStream<PeerEvent>.Continuation] = [:]

        func subscribe() -> AsyncStream<PeerEvent> {
            AsyncStream { continuation in
                let id = UUID()
                lock.lock()
                streams[id] = continuation
                lock.unlock()
                continuation.onTermination = { [weak self] _ in
                    guard let self else { return }
                    self.lock.lock()
                    self.streams[id] = nil
                    self.lock.unlock()
                }
            }
        }

        func event(event: PeerEvent) {
            lock.lock()
            let open = Array(streams.values)
            lock.unlock()
            for stream in open { stream.yield(event) }
        }
    }
}
