import Foundation

/// The words of the Apple TV Devices tab, kept pure so they test on their own.
public enum TVDevicesText {
    /// The status line under the title: "2 connected · everything synced".
    public static func status(_ state: SyncState?) -> String {
        guard let state else { return "Not connected yet" }
        let connected = state.connectedPeers == 1 ? "1 connected" : "\(state.connectedPeers) connected"
        if !state.idle { return "\(connected) · syncing" }
        if state.pendingChanges > 0 {
            let waiting = state.pendingChanges == 1 ? "1 change waiting" : "\(state.pendingChanges) changes waiting"
            return "\(connected) · \(waiting)"
        }
        return "\(connected) · everything synced"
    }

    /// The meta line of this Apple TV's row.
    public static let thisDevice = "This Apple TV · keeps a copy in its cache"

    /// The plain sentence under the list; no hint bubble.
    public static let holdHint = "Press and hold a device to remove it or rotate the key."

    /// The pair column's instruction.
    public static let pairNote = "On your iPhone or iPad: Settings › Devices › Add this iPhone to a vault, then scan this."

    /// The request column (G19), shown while this Apple TV has no vault: the eyebrow, the
    /// instruction, and the button to the typed ticket.
    public static let requestTitle = "Add this Apple TV to a vault"
    public static let requestNote =
        "On your iPhone: Settings › Devices › Add a device nearby, point it at this code, and check that the words match."
    public static let typeInstead = "Type a ticket instead"

    /// "amber · cedar · harbor · lantern · otter · quartz": the six words as one line.
    public static func wordsLine(_ words: [String]) -> String {
        words.joined(separator: " · ")
    }

    /// The confirm state of the request column: a device brought the key; the person checks the
    /// words against it and presses Select to keep the key, or Menu to refuse it.
    public static let offerTitle = "Let this device in?"
    public static let offerNote = "Check that the words match the ones on it. Select keeps the key; Menu refuses it."
    public static let keepKey = "Keep the key"

    /// "iPhone · Ada’s iPhone", or the kind alone, or "A device" when it said nothing.
    public static func offerLine(_ offer: JoinOffer) -> String {
        let kind = offer.kind.map(DevicesText.deviceWord)
        let name = offer.name?.trimmingCharacters(in: .whitespaces) ?? ""
        switch (kind, name.isEmpty) {
        case let (kind?, false): return "\(kind) · \(name)"
        case let (kind?, true): return kind
        case (nil, false): return name
        case (nil, true): return "A device"
        }
    }

    /// "Works once · new code in 9:58"; the store makes a new request when this one runs out.
    public static func requestExpiry(_ request: JoinRequest?, now: Date) -> String {
        guard let request else { return "Making a code…" }
        return "Works once · new code in \(PeerText.countdown(until: request.expiresAt, now: now))"
    }

    /// "Works once · new code in 9:58"; the store makes a new ticket when this one runs out.
    public static func expiry(_ ticket: Ticket?, now: Date) -> String {
        guard let ticket else { return "Making a ticket…" }
        return "Works once · new code in \(PeerText.countdown(until: ticket.expiresAt, now: now))"
    }

    /// The join modal's instruction and the line that points at the iPhone keyboard.
    public static let joinNote = "Type the ticket from a device that has the vault. Spaces and capitals don’t matter."
    public static let phoneKeyboard = "Easier on your iPhone: tap the keyboard notification on it and type or paste there."

    /// The first-sync screen: "Joined. Fetching the whole vault from a91c…7t0e on the local network."
    public static func fetchBody(from device: Device) -> String {
        "Joined. Fetching the whole vault from \(PeerText.shortID(device.id)) \(JoinText.reachPhrase(device.reach))."
    }

    /// The same screen at a launch that found the cache cleared and the pairing kept.
    public static let launchFetchBody = "The cache was cleared. Fetching the whole vault back from your other devices."

    public static let fetchNote = "Cards open when it’s done"

    /// Whether the first fetch is over: every bud of a known total has arrived.
    public static func fetchIsDone(received: Int, total: Int?) -> Bool {
        guard let total else { return false }
        return received >= total
    }
}
