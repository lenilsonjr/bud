import Foundation

/// Peers over memory: a stand-in for a vault with a few devices, for tests, previews and pictures.
/// Its tickets expire after their lifetime and work once; accepting one adds a fake device. A test
/// chooses which device misses a key rotation and drives fetch progress by hand.
public actor MemoryPeers: Peers {
    /// The devices of the frames, this one first.
    public static func fixtures(now: Date = Date()) -> [Device] {
        [
            Device(id: "a91cp4x8d2n6w0j3h5v9b1m7r2ks7t0e", isThisDevice: true, reach: .local, lastSeen: now),
            Device(
                id: "k7f3c8z1q5t3y7u0e4i6o2a9l5gdq2m9", reach: .direct, lastSeen: now.addingTimeInterval(-4 * 60)),
            Device(
                id: "m2pdx3v7n1b5c9z2l6k0j4h8g3fsh81k", reach: .local, lastSeen: now.addingTimeInterval(-2 * 3600)),
            Device(
                id: "t6vbr9e5w1q7y3u8i2o6p0a4s1dh2kxe", reach: .relay, lastSeen: now.addingTimeInterval(-86400)),
            Device(id: "c55wm8n4b0v6c2x9z5l1k7j3h9gf0pdl", reach: .relay, lastSeen: nil),
        ]
    }

    private struct Issued {
        var madeAt: Date
        var expiresAt: Date
        var used = false
    }

    private let lifetime: TimeInterval
    private let clock: @Sendable () -> Date
    private var all: [Device]
    private var missing: Set<String>
    private var reachable = true
    private var pendingChanges = 0
    private var syncing = false
    private var nextSummary = SyncSummary()
    private var relaySetting = RelaySetting.default
    private var issued: [String: Issued] = [:]
    private var requests: [String: Issued] = [:]
    private var requestFailure: RequestError?
    private var counter = 0

    /// The words a memory request's fingerprint is spoken in; the core has 256 of them.
    static let words = [
        "amber", "cedar", "harbor", "lantern", "meadow", "otter", "pebble", "quartz",
        "river", "saffron", "thistle", "violet", "walnut", "zephyr", "indigo", "juniper",
    ]
    private var listeners: [UUID: AsyncStream<PeerEvent>.Continuation] = [:]

    public init(
        devices: [Device]? = nil, lifetime: TimeInterval = Ticket.lifetime, missing: Set<String> = [],
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.clock = now
        self.lifetime = lifetime
        self.missing = missing
        self.all = devices ?? MemoryPeers.fixtures(now: now())
    }

    // MARK: Test controls

    /// The ids that miss the next key rotation.
    public func setMissing(_ ids: Set<String>) { missing = ids }

    /// Whether a ticket this vault issued can be reached; when not, `accept` throws `unreachable`.
    public func setReachable(_ value: Bool) { reachable = value }

    public func setPendingChanges(_ count: Int) { pendingChanges = count }

    public func setSyncing(_ value: Bool) { syncing = value }

    /// What the next `syncNow` reports.
    public func setNextSummary(_ summary: SyncSummary) { nextSummary = summary }

    /// Tells every listener that changes are arriving from a vault just joined.
    public func emitFetchProgress(received: Int, total: Int?) {
        emit(.fetchProgress(received: received, total: total))
    }

    /// What reading or confirming a request fails with from now on; nil lets them work.
    public func setRequestFailure(_ error: RequestError?) { requestFailure = error }

    // MARK: Peers

    public func devices() async throws -> [Device] { all }

    public func ticket(withAddresses: Bool) async throws -> Ticket {
        counter += 1
        var random = Generator(seed: UInt64(counter) &* 0x9E37_79B9_7F4A_7C15)
        let text = "bud1" + random.token(PeerText.ticketLength - 4)
        let qr = (0..<25).map { _ in (0..<25).map { _ in random.next() % 2 == 0 } }
        let madeAt = clock()
        let expiresAt = madeAt.addingTimeInterval(lifetime)
        issued[text] = Issued(madeAt: madeAt, expiresAt: expiresAt)
        return Ticket(text: text, qr: qr, madeAt: madeAt, expiresAt: expiresAt)
    }

    public func accept(_ text: String) async throws -> Device {
        guard PeerText.looksLikeTicket(text) else { throw AcceptError.notATicket }
        let key = String(text.filter { !$0.isWhitespace }).lowercased()
        guard reachable, var ticket = issued[key] else { throw AcceptError.unreachable }
        guard !ticket.used, clock() < ticket.expiresAt else { throw AcceptError.usedOrExpired }
        ticket.used = true
        issued[key] = ticket
        counter += 1
        var random = Generator(seed: UInt64(counter) &* 0xD1B5_4A32_D192_ED03)
        let device = Device(id: random.token(32), reach: .direct, lastSeen: clock())
        all.append(device)
        emit(.ticketRedeemed(by: device.id))
        emit(.deviceJoined(device))
        return device
    }

    public func joinRequest() async throws -> JoinRequest {
        counter += 1
        var random = Generator(seed: UInt64(counter) &* 0xA076_1D64_78BD_642F)
        let code = PeerText.requestPrefix + random.token(175)
        let qr = (0..<29).map { _ in (0..<29).map { _ in random.next() % 2 == 0 } }
        let madeAt = clock()
        let expiresAt = madeAt.addingTimeInterval(lifetime)
        requests[code] = Issued(madeAt: madeAt, expiresAt: expiresAt)
        return JoinRequest(code: code, qr: qr, words: Self.wordsOf(code), madeAt: madeAt, expiresAt: expiresAt)
    }

    public func readRequest(_ code: String) async throws -> [String] {
        guard PeerText.looksLikeRequest(code) else { throw RequestError.notARequest }
        if let requestFailure { throw requestFailure }
        let key = String(code.filter { !$0.isWhitespace }).lowercased()
        if let request = requests[key], clock() >= request.expiresAt { throw RequestError.expired }
        return Self.wordsOf(key)
    }

    public func confirmRequest(_ code: String) async throws -> Device {
        guard PeerText.looksLikeRequest(code) else { throw RequestError.notARequest }
        if let requestFailure { throw requestFailure }
        let key = String(code.filter { !$0.isWhitespace }).lowercased()
        guard reachable, var request = requests[key] else { throw RequestError.unreachable }
        guard clock() < request.expiresAt else { throw RequestError.expired }
        guard !request.used else { throw RequestError.refused }
        request.used = true
        requests[key] = request
        counter += 1
        var random = Generator(seed: UInt64(counter) &* 0xD1B5_4A32_D192_ED03)
        let device = Device(id: random.token(32), reach: .local, lastSeen: clock(), kind: .tv)
        all.append(device)
        emit(.deviceJoined(device))
        return device
    }

    /// Four words from the code alone, so the device that shows it and the one that reads it
    /// agree without talking.
    static func wordsOf(_ code: String) -> [String] {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        for byte in code.utf8 { state = (state ^ UInt64(byte)) &* 0x100_0000_01B3 }
        var random = Generator(seed: state)
        return (0..<4).map { _ in words[Int(random.next() % UInt64(words.count))] }
    }

    public func remove(_ id: String) async throws {
        guard let index = all.firstIndex(where: { $0.id == id }) else { throw PeersError.noSuchDevice(id) }
        all.remove(at: index)
        missing.remove(id)
    }

    public func rename(_ id: String, label: String?) async throws {
        guard let i = all.firstIndex(where: { $0.id == id }) else { throw PeersError.noSuchDevice(id) }
        let trimmed = label?.trimmingCharacters(in: .whitespaces) ?? ""
        all[i].label = trimmed.isEmpty ? nil : trimmed
    }

    public func allow(_ id: String) async throws {
        guard let index = all.firstIndex(where: { $0.id == id }) else { throw PeersError.noSuchDevice(id) }
        all[index].missed = false
        missing.remove(id)
    }

    public func rotateKey() async throws -> AsyncStream<RotationStep> {
        var reached = 0
        var missed: [String] = []
        var steps: [RotationStep] = []
        for index in all.indices where !all[index].isThisDevice {
            let misses = missing.contains(all[index].id)
            all[index].missed = misses
            if misses { missed.append(all[index].id) } else { reached += 1 }
            steps.append(.device(id: all[index].id, reached: !misses))
        }
        steps.append(.done(RotationResult(reached: reached, missed: missed)))
        return AsyncStream { continuation in
            for step in steps { continuation.yield(step) }
            continuation.finish()
        }
    }

    public func syncNow() async throws -> SyncSummary {
        emit(.syncFinished(nextSummary))
        return nextSummary
    }

    public func state() async throws -> SyncState {
        SyncState(
            idle: !syncing, connectedPeers: all.filter { !$0.isThisDevice && !$0.missed }.count,
            pendingChanges: pendingChanges)
    }

    public func relay() async throws -> RelaySetting { relaySetting }

    public func setRelay(_ relay: RelaySetting) async throws { relaySetting = relay }

    public func events() async throws -> AsyncStream<PeerEvent> {
        let key = UUID()
        let (stream, continuation) = AsyncStream<PeerEvent>.makeStream()
        listeners[key] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stopListening(key) }
        }
        return stream
    }

    private func stopListening(_ key: UUID) {
        listeners[key] = nil
    }

    private func emit(_ event: PeerEvent) {
        for continuation in listeners.values { continuation.yield(event) }
    }

    /// A small deterministic source of characters, so the same run makes the same tickets.
    private struct Generator {
        private var state: UInt64
        private static let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")

        init(seed: UInt64) { state = seed | 1 }

        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 33
        }

        mutating func token(_ length: Int) -> String {
            String((0..<length).map { _ in Generator.alphabet[Int(next() % UInt64(Generator.alphabet.count))] })
        }
    }
}
