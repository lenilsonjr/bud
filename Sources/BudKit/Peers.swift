import Foundation

/// How far a device is from this one, as the pairing screens show it.
public enum Reach: String, Codable, Sendable {
    case local, relay, direct
}

/// The sort of device, once the core carries it.
public enum DeviceKind: String, CaseIterable, Codable, Sendable {
    case mac, iphone, ipad, tv
}

/// A device paired with this vault. `name` and `kind` come from the device itself in its first
/// session and are nil until then; `label` is this vault's own word for it.
public struct Device: Identifiable, Hashable, Sendable {
    public var id: String
    public var isThisDevice: Bool
    public var reach: Reach
    public var lastSeen: Date?
    /// The last key rotation could not move this device: it holds the old key.
    public var missed: Bool
    /// The name the device's system gives it, as the device sent it.
    public var name: String?
    public var kind: DeviceKind?
    /// The label this vault gave the device, shown instead of `name` when set.
    public var label: String?

    public init(
        id: String, isThisDevice: Bool = false, reach: Reach = .direct, lastSeen: Date? = nil, missed: Bool = false,
        name: String? = nil, kind: DeviceKind? = nil, label: String? = nil
    ) {
        self.id = id
        self.isThisDevice = isThisDevice
        self.reach = reach
        self.lastSeen = lastSeen
        self.missed = missed
        self.name = name
        self.kind = kind
        self.label = label
    }

    /// What a row leads with: the label, else the name, else nothing (the row shows the id).
    public var displayName: String? {
        let label = label?.trimmingCharacters(in: .whitespaces) ?? ""
        if !label.isEmpty { return label }
        let name = name?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? nil : name
    }
}

/// A pairing ticket: the text to type, the modules of its QR code (`true` is dark) and when it
/// stops working.
public struct Ticket: Hashable, Sendable {
    /// How long a ticket works, in seconds.
    public static let lifetime: TimeInterval = 600

    public var text: String
    public var qr: [[Bool]]
    public var madeAt: Date
    public var expiresAt: Date

    public init(text: String, qr: [[Bool]], madeAt: Date, expiresAt: Date? = nil) {
        self.text = text
        self.qr = qr
        self.madeAt = madeAt
        self.expiresAt = expiresAt ?? madeAt.addingTimeInterval(Ticket.lifetime)
    }
}

/// What a device without the vault shows to be let in (G19): the code for the device with the
/// vault to scan, the modules of its QR code (`true` is dark), the six words both sides show, and
/// when it stops working.
public struct JoinRequest: Hashable, Sendable {
    /// How long a request works, in seconds; the same as a ticket.
    public static let lifetime: TimeInterval = Ticket.lifetime

    public var code: String
    public var qr: [[Bool]]
    public var words: [String]
    public var madeAt: Date
    public var expiresAt: Date

    public init(code: String, qr: [[Bool]], words: [String], madeAt: Date, expiresAt: Date? = nil) {
        self.code = code
        self.qr = qr
        self.words = words
        self.madeAt = madeAt
        self.expiresAt = expiresAt ?? madeAt.addingTimeInterval(JoinRequest.lifetime)
    }
}

/// The key a device with the vault brought to the request this one shows: who brought it and the
/// words of the request, for the person at this device to keep or refuse.
public struct JoinOffer: Hashable, Sendable {
    public var id: String
    public var kind: DeviceKind?
    public var name: String?
    public var words: [String]

    public init(id: String, kind: DeviceKind? = nil, name: String? = nil, words: [String]) {
        self.id = id
        self.kind = kind
        self.name = name
        self.words = words
    }
}

/// Why a join request could not be read or confirmed.
public enum RequestError: Error, Equatable, Sendable {
    /// The code does not start like a request, or is damaged.
    case notARequest
    /// The request is past its lifetime, or was this vault's own.
    case expired
    /// The device that showed it could not be reached, or did not answer.
    case unreachable
    /// The device turned the key away: the request was used, or it is paired already.
    case refused

    /// The case the core's message stands for, or nil for a message that is none of them.
    public init?(message: String) {
        let text = message.lowercased()
        if text.contains("not a join request") {
            self = .notARequest
        } else if text.contains("past its lifetime") || text.contains("this vault's") {
            self = .expired
        } else if text.contains("did not answer") || text.contains("could not reach") || text.contains("connect") {
            self = .unreachable
        } else if text.contains("did not confirm") || text.contains("refused") || text.contains("paired") {
            self = .refused
        } else {
            return nil
        }
    }

    /// The error as one of the cases, with an unknown one read as the device not answering.
    public init(_ error: Error) {
        if let known = error as? RequestError {
            self = known
        } else {
            self = RequestError(message: String(describing: error)) ?? .unreachable
        }
    }
}

/// Why a ticket could not be accepted: the three cases the pairing frames name.
public enum AcceptError: Error, Equatable, Sendable {
    /// The text does not start like a ticket, or is damaged.
    case notATicket
    /// The vault that made it turned it away: it was used or it ran out.
    case usedOrExpired
    /// The vault that made it could not be found.
    case unreachable

    /// The case the core's message stands for, or nil for a message that is none of them.
    public init?(message: String) {
        let text = message.lowercased()
        if text.contains("not a pairing ticket") {
            self = .notATicket
        } else if text.contains("refused") {
            self = .usedOrExpired
        } else if text.contains("could not reach") {
            self = .unreachable
        } else {
            return nil
        }
    }
}

public enum PeersError: Error, Equatable, Sendable {
    case noSuchDevice(String)
    /// No key is on offer to answer.
    case nothingOffered
}

/// How this node reaches peers that are not on the same network.
public enum RelaySetting: Hashable, Sendable {
    case `default`
    case custom(URL)
    case off
}

/// What a node is doing.
public struct SyncState: Hashable, Sendable {
    public var idle: Bool
    public var connectedPeers: Int
    public var pendingChanges: Int

    public init(idle: Bool, connectedPeers: Int, pendingChanges: Int) {
        self.idle = idle
        self.connectedPeers = connectedPeers
        self.pendingChanges = pendingChanges
    }
}

/// What one sync did.
public struct SyncSummary: Hashable, Sendable {
    public var created: Int
    public var updated: Int
    public var written: Int
    public var moved: Int
    public var ops: Int

    public init(created: Int = 0, updated: Int = 0, written: Int = 0, moved: Int = 0, ops: Int = 0) {
        self.created = created
        self.updated = updated
        self.written = written
        self.moved = moved
        self.ops = ops
    }
}

/// The end of a key rotation: how many devices took the new key, and the ids that did not.
public struct RotationResult: Hashable, Sendable {
    public var reached: Int
    public var missed: [String]

    public init(reached: Int, missed: [String]) {
        self.reached = reached
        self.missed = missed
    }
}

/// One step of a key rotation: a device tried, and at the end the result.
public enum RotationStep: Hashable, Sendable {
    case device(id: String, reached: Bool)
    case done(RotationResult)

    public var deviceID: String? {
        if case let .device(id, _) = self { return id }
        return nil
    }
}

/// Something a node tells the app about.
public enum PeerEvent: Hashable, Sendable {
    /// A device used the ticket this one showed.
    case ticketRedeemed(by: String)
    case deviceJoined(Device)
    /// A device with the vault brought its key to the request this one shows; it is kept only on
    /// `answerJoin`.
    case joinOffered(JoinOffer)
    case syncFinished(SyncSummary)
    /// Changes arriving from a vault just joined; `total` is nil while it is not known.
    case fetchProgress(received: Int, total: Int?)
}

/// Where BudKit pairs devices and reads who is paired. It mirrors what the Rust bindings export on
/// a peer node; the app plugs in the real one and the pairing screens never touch the network.
public protocol Peers: Sendable {
    func devices() async throws -> [Device]
    /// A new ticket. With addresses it carries where this node listens, for a device that cannot
    /// look it up.
    func ticket(withAddresses: Bool) async throws -> Ticket
    /// Pairs with the vault that made the ticket. Throws `AcceptError`.
    func accept(_ text: String) async throws -> Device
    /// Shows a join request for a device that holds the vault to scan; it replaces the one shown
    /// before, lasts as long as a ticket, and is good once.
    func joinRequest() async throws -> JoinRequest
    /// Reads a request another device shows: its six words, for the person to confirm against
    /// the device's. Nothing moves until `confirmRequest`. Throws `RequestError`.
    func readRequest(_ code: String) async throws -> [String]
    /// The person confirmed the words: brings this vault's key to the device that showed the
    /// request and remembers it. Throws `RequestError`.
    func confirmRequest(_ code: String) async throws -> Device
    /// The person at this device answered the key on offer: kept, the device that brought it is
    /// a peer; refused, the request stays on show.
    func answerJoin(keep: Bool) async throws
    func remove(_ id: String) async throws
    /// Gives a device a label of this vault's own; nil or empty takes it away.
    func rename(_ id: String, label: String?) async throws
    /// Lets a device the last rotation turned away back in.
    func allow(_ id: String) async throws
    /// Makes a new vault key and gives it to every device; the stream ends with `.done`.
    func rotateKey() async throws -> AsyncStream<RotationStep>
    func syncNow() async throws -> SyncSummary
    func state() async throws -> SyncState
    func relay() async throws -> RelaySetting
    func setRelay(_ relay: RelaySetting) async throws
    func events() async throws -> AsyncStream<PeerEvent>
}
