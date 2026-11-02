import Foundation
#if canImport(Combine)
import Combine
#endif

/// How the app is drawn: with the system, or always light or dark.
public enum Appearance: String, CaseIterable, Sendable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}

/// How much of a phone's height the file navigator takes above the page: 30 / 70 or 40 / 60.
/// A flag while the two are tried on a device.
public enum PhoneSplit: String, CaseIterable, Sendable {
    case thirty = "30 / 70"
    case forty = "40 / 60"

    /// The navigator's share of the height.
    public var share: Double {
        switch self {
        case .thirty: return 0.3
        case .forty: return 0.4
        }
    }
}

#if canImport(Combine)
/// The person's choices and the flags for layouts under test, kept in `UserDefaults` and read
/// through the environment, so a view can switch on one in one line. Each has a default, so a
/// fresh install and an old one both work.
@MainActor
public final class Flags: ObservableObject {
    public static let shared = Flags()

    enum Key {
        static let appearance = "bud.appearance"
        static let phoneSplit = "bud.try.phoneSplit"
    }

    private let defaults: UserDefaults

    @Published public var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    @Published public var phoneSplit: PhoneSplit {
        didSet { defaults.set(phoneSplit.rawValue, forKey: Key.phoneSplit) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Key.appearance).flatMap(Appearance.init(rawValue:)) ?? .system
        phoneSplit = defaults.string(forKey: Key.phoneSplit).flatMap(PhoneSplit.init(rawValue:)) ?? .thirty
    }
}
#endif
