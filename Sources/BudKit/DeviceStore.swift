import Foundation
#if canImport(Combine)
import Combine
#endif

/// Where the join screen is.
public enum JoinPhase: Equatable, Sendable {
    case idle
    case checking
    case failed(AcceptError)
    /// Paired; `received` of `total` changes have arrived, with `total` nil while it is not known.
    case joined(Device, received: Int, total: Int?)
}

/// Where the phone's scan of a join request is.
public enum RequestPhase: Equatable, Sendable {
    case idle
    case reading
    /// The code was read; the person compares these words with the device's.
    case words([String], code: String)
    case confirming
    case confirmed(Device)
    case failed(RequestError)
}

/// How far a key rotation has got, for the dialog.
public struct RotationProgress: Equatable, Sendable {
    /// How many devices it has to reach.
    public var total: Int
    /// How many it has tried so far.
    public var done: Int
    /// What each device tried answered: true when it took the new key.
    public var reports: [String: Bool]
    /// Set once the rotation is over.
    public var result: RotationResult?

    public init(total: Int, done: Int = 0, reports: [String: Bool] = [:], result: RotationResult? = nil) {
        self.total = total
        self.done = done
        self.reports = reports
        self.result = result
    }
}

/// What the pairing screens read: the devices, the sync state, the ticket on show, the join and the
/// rotation. Every change goes to the `Peers` and what is shown is what comes back.
@MainActor
public final class DeviceStore: ObservableObject {
    @Published public private(set) var devices: [Device] = []
    @Published public private(set) var syncState: SyncState?
    @Published public private(set) var lastSummary: SyncSummary?
    /// The ticket on show while a sheet asks for one; it is replaced when it expires.
    @Published public private(set) var currentTicket: Ticket?
    @Published public private(set) var joinPhase: JoinPhase = .idle
    @Published public private(set) var rotation: RotationProgress?
    /// When the last rotation that left a device behind was over, for the notice above the list.
    @Published public private(set) var rotatedAt: Date?
    @Published public private(set) var relay: RelaySetting = .default
    /// The device that used the ticket on show, until the sheet is closed or asks again.
    @Published public private(set) var redeemedBy: String?
    /// The join request on show while this device asks to be let in; replaced when it expires.
    @Published public private(set) var currentRequest: JoinRequest?
    /// The key a device brought to the request on show, until the person keeps or refuses it.
    @Published public private(set) var offer: JoinOffer?
    /// Where the scan of another device's request is, on the device that holds the vault.
    @Published public private(set) var requestPhase: RequestPhase = .idle
    /// Told when a sync is over, for the toast that says what it brought in.
    public var onSyncFinished: ((SyncSummary) -> Void)?
    /// Told when a key rotation is over, for the toast that says who missed it.
    public var onRotationFinished: ((RotationResult) -> Void)?

    private var peers: Peers
    private let now: @Sendable () -> Date
    private var listening: Task<Void, Never>?
    private var renewing: Task<Void, Never>?
    private var renewingRequest: Task<Void, Never>?
    private var sheetOpen = false
    private var requestOpen = false
    /// Counts the phone's scans: a read or confirmation that comes back after the sheet was reset
    /// belongs to an old one and is dropped.
    private var scan = 0
    private var withAddresses = false
    private var fetched: (received: Int, total: Int?) = (0, nil)

    /// The store the apps use. It starts on this device alone, so Settings shows the invitation,
    /// and the app hands it the real node once that has started (`use`); pictures keep it alone.
    public static let shared = DeviceStore(peers: MemoryPeers.forLaunch(arguments: ProcessInfo.processInfo.arguments))

    public init(peers: Peers, now: @escaping @Sendable () -> Date = { Date() }) {
        self.peers = peers
        self.now = now
    }

    deinit {
        listening?.cancel()
        renewing?.cancel()
        renewingRequest?.cancel()
    }

    /// "k7f3…q2m9": the first four characters of an id, an ellipsis and the last four.
    public func shortID(_ id: String) -> String { PeerText.shortID(id) }

    /// Follows another node from now on: the app's own, once it has started.
    public func use(_ peers: Peers) async {
        self.peers = peers
        await start()
    }

    /// Loads the devices and starts following what the node says.
    public func start() async {
        listening?.cancel()
        let events = try? await peers.events()
        await refresh()
        guard let events else { return }
        listening = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    public func stop() {
        listening?.cancel()
        listening = nil
        closeTicket()
        closeRequest()
    }

    /// Reads the devices and the sync state again.
    public func refresh() async {
        if let list = try? await peers.devices() { devices = list }
        if let state = try? await peers.state() { syncState = state }
        if let setting = try? await peers.relay() { relay = setting }
    }

    public func setRelay(_ setting: RelaySetting) async {
        try? await peers.setRelay(setting)
        if let stored = try? await peers.relay() { relay = stored }
    }

    public func syncNow() async {
        if let summary = try? await peers.syncNow() { lastSummary = summary }
        await refresh()
    }

    // MARK: Ticket

    /// A sheet asks for a ticket: makes one and keeps it fresh until `closeTicket`.
    public func openTicket(withAddresses: Bool = false) async {
        sheetOpen = true
        self.withAddresses = withAddresses
        redeemedBy = nil
        await renewTicket()
    }

    public func closeTicket() {
        sheetOpen = false
        renewing?.cancel()
        renewing = nil
        currentTicket = nil
    }

    /// Makes a new ticket if the sheet is open and the one on show has run out.
    public func refreshTicketIfExpired() async {
        guard sheetOpen, currentTicket.map({ $0.expiresAt <= now() }) ?? true else { return }
        await renewTicket()
    }

    private func renewTicket() async {
        guard let ticket = try? await peers.ticket(withAddresses: withAddresses), sheetOpen else { return }
        currentTicket = ticket
        renewing?.cancel()
        let wait = max(0, ticket.expiresAt.timeIntervalSince(now()))
        renewing = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.refreshTicketIfExpired()
        }
    }

    // MARK: Join request

    /// This device asks to be let in: shows a request and keeps it fresh until `closeRequest`.
    public func openRequest() async {
        requestOpen = true
        await renewRequest()
    }

    public func closeRequest() {
        requestOpen = false
        renewingRequest?.cancel()
        renewingRequest = nil
        currentRequest = nil
        offer = nil
    }

    /// The person at this device kept or refused the key on offer. Refused, the request stays on
    /// show for another try.
    public func answerJoin(keep: Bool) async {
        guard offer != nil else { return }
        offer = nil
        try? await peers.answerJoin(keep: keep)
    }

    /// Makes a new request if one is on show and the one shown has run out.
    public func refreshRequestIfExpired() async {
        guard requestOpen, currentRequest.map({ $0.expiresAt <= now() }) ?? true else { return }
        await renewRequest()
    }

    private func renewRequest() async {
        guard let request = try? await peers.joinRequest(), requestOpen else { return }
        currentRequest = request
        renewingRequest?.cancel()
        let wait = max(0, request.expiresAt.timeIntervalSince(now()))
        renewingRequest = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.refreshRequestIfExpired()
        }
    }

    /// On the device with the vault: reads the request the person scanned and puts its words up.
    public func readRequest(_ code: String) async {
        let mine = scan
        requestPhase = .reading
        let phase: RequestPhase
        do {
            phase = .words(try await peers.readRequest(code), code: code)
        } catch {
            phase = .failed(RequestError(error))
        }
        if scan == mine { requestPhase = phase }
    }

    /// The person confirmed the words match: brings the key over to the device that asked.
    public func confirmRequest() async {
        guard case let .words(_, code) = requestPhase else { return }
        let mine = scan
        requestPhase = .confirming
        do {
            let device = try await peers.confirmRequest(code)
            if scan == mine { requestPhase = .confirmed(device) }
            await refresh()
        } catch {
            if scan == mine { requestPhase = .failed(RequestError(error)) }
        }
    }

    /// Back to nothing scanned; a read or confirmation still running is dropped when it ends.
    public func resetRequest() {
        scan += 1
        requestPhase = .idle
    }

    // MARK: Join

    /// Pairs with the vault that made the ticket the person typed or scanned.
    public func join(text: String) async {
        joinPhase = .checking
        fetched = (0, nil)
        do {
            let device = try await peers.accept(text)
            joinPhase = .joined(device, received: fetched.received, total: fetched.total)
            await refresh()
        } catch let error as AcceptError {
            joinPhase = .failed(error)
        } catch {
            joinPhase = .failed(AcceptError(message: String(describing: error)) ?? .unreachable)
        }
    }

    public func resetJoin() {
        joinPhase = .idle
        fetched = (0, nil)
    }

    // MARK: Remove, allow, rotate

    /// Forgets a device, and with `rotate` makes a new key so it cannot read what comes next. A
    /// removal the node refuses returns false and starts no rotation.
    @discardableResult
    public func remove(_ id: String, rotate: Bool) async -> Bool {
        do {
            try await peers.remove(id)
        } catch {
            await refresh()
            return false
        }
        await refresh()
        if rotate { await rotateKey() }
        return true
    }

    /// Makes a new key and sends it to the devices that remain; `rotation` follows each one.
    /// Gives a device a label of this vault's own; nil or empty takes it away.
    public func rename(_ id: String, label: String?) async {
        try? await peers.rename(id, label: label)
        await refresh()
    }

    public func rotateKey() async {
        let total = devices.filter { !$0.isThisDevice }.count
        rotation = RotationProgress(total: total)
        guard let steps = try? await peers.rotateKey() else {
            rotation = nil
            return
        }
        for await step in steps {
            switch step {
            case let .device(id, reached):
                rotation?.done += 1
                rotation?.reports[id] = reached
            case let .done(result):
                rotation?.result = result
                if !result.missed.isEmpty { rotatedAt = now() }
                onRotationFinished?(result)
            }
        }
        await refresh()
    }

    public func dismissRotation() { rotation = nil }

    /// Lets a device the last rotation turned away back in.
    public func allow(_ id: String) async {
        try? await peers.allow(id)
        await refresh()
    }

    // MARK: Events

    func handle(_ event: PeerEvent) async {
        switch event {
        case let .ticketRedeemed(id):
            redeemedBy = id
            await refresh()
        case let .joinOffered(offered):
            if requestOpen { offer = offered }
        case let .deviceJoined(device):
            if requestOpen {
                // The device that scanned this one's request brought the key and the person kept
                // it: the first fetch begins, as it does after a ticket.
                closeRequest()
                fetched = (0, nil)
                joinPhase = .joined(device, received: 0, total: nil)
            }
            await refresh()
        case let .syncFinished(summary):
            lastSummary = summary
            onSyncFinished?(summary)
            await refresh()
        case let .fetchProgress(received, total):
            fetched = (received, total)
            if case let .joined(device, _, _) = joinPhase {
                joinPhase = .joined(device, received: received, total: total)
            }
        }
    }
}
