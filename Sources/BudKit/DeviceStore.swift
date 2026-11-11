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

/// How far the first fetch of a launch has got: `received` of `total` changes, with `total` nil
/// while it is not known.
public struct LaunchFetch: Equatable, Sendable {
    public var received: Int
    public var total: Int?

    public init(received: Int, total: Int?) {
        self.received = received
        self.total = total
    }
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
    /// Set while a launch that found its vault cleared waits for the first fetch from its peers:
    /// what has arrived of how much, with `total` nil while it is not known.
    @Published public private(set) var launchFetch: LaunchFetch?
    /// Told when a sync is over, for the toast that says what it brought in.
    public var onSyncFinished: ((SyncSummary) -> Void)?
    /// Told when a key rotation is over, for the toast that says who missed it.
    public var onRotationFinished: ((RotationResult) -> Void)?
    /// Told when this device paired, or a peer was removed, renamed, let back in or given a new
    /// key, or another device removed this one: for the copy of the pairing kept outside the
    /// vault.
    public var onPairingChanged: (() -> Void)?
    /// Told when this device, which had other devices, has none left: removed here, or gone
    /// from the node's list any other way. The kept pairing goes.
    public var onUnpaired: (() -> Void)?

    private var peers: Peers
    /// Where the store, and the bud store over it, read the time; a picture hands it a fixed moment.
    public let now: @Sendable () -> Date
    /// The calendar the days are counted in, beside the clock: the system's, or the one a picture
    /// fixes, so every view counts days the same way.
    public let calendar: Calendar
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
    /// Counts the starts, so one that finishes after a newer one began does not listen too.
    private var starts = 0
    /// Ends the launch fetch when nothing has moved for a while.
    private var launchFetchTimer: Task<Void, Never>?
    /// How long the launch fetch waits with no progress, once the node is up; nil before.
    private var launchPatience: TimeInterval?

    /// How long the launch fetch waits for a node that dials `peers` peers one after another,
    /// each session given up after `sessionTimeout` seconds: all of them, and one more session,
    /// so the last peer that is there still ends before the wait gives up.
    nonisolated public static func launchFetchPatience(peers: Int, sessionTimeout: TimeInterval) -> TimeInterval {
        TimeInterval(max(peers, 1) + 1) * sessionTimeout
    }

    /// The store the apps use. It starts on this device alone, so Settings shows the invitation,
    /// and the app hands it the real node once that has started (`use`); pictures keep it alone.
    public static let shared = DeviceStore(peers: MemoryPeers.forLaunch(arguments: ProcessInfo.processInfo.arguments))

    public init(peers: Peers, now: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .current) {
        self.peers = peers
        self.now = now
        self.calendar = calendar
    }

    deinit {
        listening?.cancel()
        renewing?.cancel()
        renewingRequest?.cancel()
        launchFetchTimer?.cancel()
    }

    /// "k7f3…q2m9": the first four characters of an id, an ellipsis and the last four.
    public func shortID(_ id: String) -> String { PeerText.shortID(id) }

    /// Follows another node from now on: the app's own, once it has started.
    /// A ticket or request on show came from the node before, which cannot pair: the new node
    /// makes its own, and if it cannot yet the old one is not left on show.
    public func use(_ peers: Peers) async {
        self.peers = peers
        currentTicket = nil
        currentRequest = nil
        await start()
        if sheetOpen { await renewTicket() }
        if requestOpen { await renewRequest() }
    }

    /// Loads the devices and starts following what the node says.
    /// Safe to call again while one is under way: only the latest start listens, and a stream
    /// an older one opened is let go unheard.
    public func start() async {
        starts += 1
        let mine = starts
        listening?.cancel()
        listening = nil
        let events = try? await peers.events()
        guard mine == starts else { return }
        await refresh()
        guard let events, mine == starts else { return }
        listening = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    public func stop() {
        starts += 1
        listening?.cancel()
        listening = nil
        closeTicket()
        closeRequest()
    }

    /// Reads the devices and the sync state again.
    public func refresh() async {
        if let list = try? await peers.devices() {
            let hadOthers = devices.contains { !$0.isThisDevice }
            devices = list
            if hadOthers && list.allSatisfy(\.isThisDevice) { onUnpaired?() }
        }
        if let state = try? await peers.state() { syncState = state }
        if let setting = try? await peers.relay() { relay = setting }
    }

    public func setRelay(_ setting: RelaySetting) async {
        try? await peers.setRelay(setting)
        if let stored = try? await peers.relay() { relay = stored }
    }

    /// Syncs with every peer now. One that answered ends a launch fetch, whatever it brought:
    /// it holds everything the peer had. So does a sync with no peer to ask. A sync that reached
    /// no peer leaves the wait to its patience, which gives every peer its session: a peer that
    /// failed at once may be back on the node's next round.
    public func syncNow() async {
        if let summary = try? await peers.syncNow() {
            lastSummary = summary
            endLaunchFetch()
        }
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
        if keep { onPairingChanged?() }
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
            onPairingChanged?()
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
            onPairingChanged?()
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

    // MARK: Launch fetch

    /// The vault came up cleared and its pairing comes back: the cards wait for the first fetch.
    /// The patience starts once the node is up (`startLaunchFetchPatience`), so a slow start
    /// does not eat into it.
    public func awaitLaunchFetch() {
        launchPatience = nil
        launchFetch = LaunchFetch(received: 0, total: nil)
    }

    /// The node is up: the wait ends after a while with nothing arriving, so a peer that is not
    /// around never holds the screen. The while is sized to the peers listed now, each given
    /// `sessionTimeout` seconds, the core's own. Each bit of progress starts it over; the core
    /// tells no session before it ends, so that is the only sign of life there is.
    public func startLaunchFetchPatience(sessionTimeout: TimeInterval) {
        let peers = devices.filter { !$0.isThisDevice }.count
        launchPatience = Self.launchFetchPatience(peers: peers, sessionTimeout: sessionTimeout)
        waitForLaunchFetch()
    }

    /// Something may have changed what this device keeps of its pairing, such as the app going
    /// to the background: the copy kept elsewhere is brought up to date.
    public func pairingMayHaveChanged() {
        onPairingChanged?()
    }

    /// The cards open, fetched or not: the fetch is over, or the person stopped waiting for it.
    public func endLaunchFetch() {
        launchFetchTimer?.cancel()
        launchFetchTimer = nil
        launchFetch = nil
    }

    /// Starts the patience over, after progress.
    private func waitForLaunchFetch() {
        launchFetchTimer?.cancel()
        guard launchFetch != nil, let patience = launchPatience else { return }
        launchFetchTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(patience * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.endLaunchFetch()
        }
    }

    /// A first session tells its progress twice, before and after it applies what came, so
    /// anything received means the fetch from that peer is over, its size known or not.
    static func launchFetchIsDone(received: Int, total: Int?) -> Bool {
        received > 0 || TVDevicesText.fetchIsDone(received: received, total: total)
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
        onPairingChanged?()
        if rotate { await rotateKey() }
        return true
    }

    /// Makes a new key and sends it to the devices that remain; `rotation` follows each one.
    /// Gives a device a label of this vault's own; nil or empty takes it away.
    public func rename(_ id: String, label: String?) async {
        try? await peers.rename(id, label: label)
        await refresh()
        onPairingChanged?()
    }

    public func rotateKey() async {
        let total = devices.filter { !$0.isThisDevice }.count
        rotation = RotationProgress(total: total)
        guard let steps = try? await peers.rotateKey() else {
            rotation = nil
            onRotationFinished?(RotationResult(reached: 0, missed: [], failed: true))
            return
        }
        for await step in steps {
            switch step {
            case let .device(id, reached):
                rotation?.done += 1
                rotation?.reports[id] = reached
            case let .removed(id):
                // Not one to reach any more: it leaves the count and the list.
                rotation?.total -= 1
                devices.removeAll { $0.id == id }
            case let .done(result):
                rotation?.result = result
                if result.failed { rotation = nil }
                if !result.failed && !result.missed.isEmpty { rotatedAt = now() }
                onRotationFinished?(result)
                onPairingChanged?()
            }
        }
        await refresh()
    }

    public func dismissRotation() { rotation = nil }

    /// Lets a device the last rotation turned away back in.
    public func allow(_ id: String) async {
        try? await peers.allow(id)
        await refresh()
        onPairingChanged?()
    }

    // MARK: Events

    func handle(_ event: PeerEvent) async {
        switch event {
        case let .ticketRedeemed(id):
            redeemedBy = id
            await refresh()
            onPairingChanged?()
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
            onPairingChanged?()
        case let .syncFinished(summary):
            lastSummary = summary
            // A sync that brought buds in ends the wait, even one that never said its size.
            endLaunchFetch()
            onSyncFinished?(summary)
            await refresh()
        case .pairingChanged:
            onPairingChanged?()
        case let .deviceRemoved(id):
            // Gone from the node's list. The last one gone unpairs this device, which the refresh
            // tells, and leaves no one to wait for a launch fetch from. A refresh that failed
            // leaves the device listed, so it goes here all the same.
            await refresh()
            if devices.contains(where: { $0.id == id }) {
                devices.removeAll { $0.id == id }
                if devices.allSatisfy(\.isThisDevice) { onUnpaired?() }
            }
            if devices.contains(where: { !$0.isThisDevice }) {
                onPairingChanged?()
            } else {
                endLaunchFetch()
            }
        case let .fetchProgress(received, total):
            fetched = (received, total)
            if case let .joined(device, _, _) = joinPhase {
                joinPhase = .joined(device, received: received, total: total)
            }
            if launchFetch != nil {
                if Self.launchFetchIsDone(received: received, total: total) {
                    endLaunchFetch()
                } else {
                    launchFetch = LaunchFetch(received: received, total: total)
                    waitForLaunchFetch()
                }
            }
        }
    }
}
