import Foundation

/// The words and small decisions of Settings › Devices, kept pure so they test on their own.
public enum DevicesText {
    /// The sort of device this build runs on; `isPad` says an iOS build is on an iPad, which only
    /// a view can tell.
    public static func platform(isPad: Bool) -> DeviceKind {
        #if os(iOS)
        return isPad ? .ipad : .iphone
        #elseif os(tvOS)
        return .tv
        #else
        return .mac
        #endif
    }

    /// "This Mac", "This iPhone", "This iPad".
    public static func thisDevice(_ kind: DeviceKind?) -> String {
        switch kind {
        case .mac: return "This Mac"
        case .iphone: return "This iPhone"
        case .ipad: return "This iPad"
        case .tv: return "This Apple TV"
        case nil: return "This device"
        }
    }

    /// The line under DEVICES, always shown.
    public static let intro =
        "Devices that hold this vault’s key sync with each other, on the same network or through a relay. Nobody else can read what they send."

    /// The caption under the Relay control.
    public static let relayCaption = "Carries traffic when devices are apart. It can’t read it."

    /// The empty state's headline: "Only this Mac has the vault so far".
    public static func alone(_ kind: DeviceKind?) -> String {
        "Only this \(deviceWord(kind)) has the vault so far"
    }

    /// The empty state's invitation, naming the other three kinds of device.
    public static func invitation(_ kind: DeviceKind?) -> String {
        let others = DeviceKind.allCases.filter { $0 != kind }.map(deviceWord)
        let list = others.dropLast().joined(separator: ", ") + " or " + (others.last ?? "")
        return "Show a ticket here and take it on your \(list). If your vault already lives on another device, add this \(deviceWord(kind)) to it instead."
    }

    /// The word the invitation uses: "Add this Mac to a vault".
    public static func deviceWord(_ kind: DeviceKind?) -> String {
        switch kind {
        case .mac: return "Mac"
        case .iphone: return "iPhone"
        case .ipad: return "iPad"
        case .tv: return "Apple TV"
        case nil: return "device"
        }
    }

    /// How a device is reached, in words.
    public static func reachWord(_ reach: Reach) -> String {
        switch reach {
        case .local: return "Local network"
        case .relay: return "Through a relay"
        case .direct: return "Direct"
        }
    }

    /// The row's second line: "This Mac · holds the vault", "Local network · seen just now",
    /// "Through a relay · not seen yet", or "Missed the new key".
    public static func rowCaption(_ device: Device, kind: DeviceKind?, now: Date) -> String {
        if device.isThisDevice { return "\(thisDevice(kind)) · holds the vault" }
        if device.missed { return "Missed the new key" }
        return "\(reachWord(device.reach)) · \(PeerText.seen(device.lastSeen, now: now))"
    }

    /// The toast after a sync that brought changes: "3 changes arrived"; nil when none did.
    public static func arrival(_ summary: SyncSummary) -> String? {
        let changes = summary.created + summary.updated + summary.written + summary.moved
        guard changes > 0 else { return nil }
        return changes == 1 ? "1 change arrived" : "\(changes) changes arrived"
    }

    /// The toast after a key rotation: who missed it, or how many took it.
    public static func rotated(_ result: RotationResult) -> String {
        switch result.missed.count {
        case 0: return result.reached == 1 ? "Key rotated · 1 device got it" : "Key rotated · \(result.reached) devices got it"
        case 1: return "Key rotated · 1 device missed it"
        case let n: return "Key rotated · \(n) devices missed it"
        }
    }

    /// One line of the Rotating the key dialog.
    public struct RotationLine: Equatable, Sendable {
        public enum State: Equatable, Sendable { case newKey, gotIt, waiting, missed }
        public var id: String
        public var state: State
        public var label: String
    }

    /// The dialog's lines: this device first with the new key, then each of the others as it
    /// reports. A device that has not answered yet waits; one that is apart says so.
    public static func rotationLines(_ devices: [Device], progress: RotationProgress?, kind: DeviceKind?) -> [RotationLine] {
        ordered(devices).map { device in
            if device.isThisDevice { return RotationLine(id: device.id, state: .newKey, label: "\(thisDevice(kind)) · new key") }
            switch progress?.reports[device.id] {
            case .some(true): return RotationLine(id: device.id, state: .gotIt, label: "Got it")
            case .some(false): return RotationLine(id: device.id, state: .missed, label: "Didn’t answer · missed the new key")
            case .none:
                let how = device.reach == .relay ? "apart, through a relay" : "on the \(reachWord(device.reach).lowercased())"
                return RotationLine(id: device.id, state: .waiting, label: "Waiting · \(how)")
            }
        }
    }

    /// "2 of 3": the devices that have the new key, this one included, of all of them.
    public static func rotationCount(_ progress: RotationProgress?) -> String {
        let reached = progress.map { $0.reports.values.filter { $0 }.count } ?? 0
        let total = progress?.total ?? 0
        return "\(reached + 1) of \(total + 1)"
    }

    /// This device first, the others as they came.
    public static func ordered(_ devices: [Device]) -> [Device] {
        devices.filter(\.isThisDevice) + devices.filter { !$0.isThisDevice }
    }

    /// Whether there is no other device: the invitation shows instead of a list.
    public static func isEmpty(_ devices: [Device]) -> Bool {
        !devices.contains { !$0.isThisDevice }
    }

    /// The line above the list when a rotation left devices behind; nil when none did.
    public static func notice(missed: Int, since: Date?, timeZone: TimeZone = .current) -> String? {
        guard missed > 0 else { return nil }
        let when = since.map { "New key since \(clock($0, timeZone: timeZone))." } ?? "New key."
        let who = missed == 1 ? "1 device missed it and needs" : "\(missed) devices missed it and need"
        return "\(when) \(who) a fresh ticket."
    }

    private static func clock(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        return "\(hour):" + (minute < 10 ? "0" : "") + "\(minute)"
    }

}

/// The three choices of the Relay control.
public enum RelayChoice: CaseIterable, Hashable, Sendable {
    case publicRelays, custom, off

    public var title: String {
        switch self {
        case .publicRelays: return "Public relays"
        case .custom: return "Custom by URL"
        case .off: return "Off"
        }
    }

    public init(_ setting: RelaySetting) {
        switch setting {
        case .default: self = .publicRelays
        case .custom: self = .custom
        case .off: self = .off
        }
    }

    /// The URL a person typed, when it is an http or https address with a host.
    public static func url(from text: String) -> URL? {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: typed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
            let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}
