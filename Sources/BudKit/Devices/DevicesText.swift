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
