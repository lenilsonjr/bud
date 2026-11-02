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

#if canImport(Combine)
/// The person's choices, kept in `UserDefaults` and read through the environment. Each has a
/// default, so a fresh install and an old one both work. A layout under test goes here as a flag
/// until one way is kept.
@MainActor
public final class Flags: ObservableObject {
    public static let shared = Flags()

    enum Key {
        static let appearance = "bud.appearance"
    }

    private let defaults: UserDefaults

    @Published public var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Key.appearance).flatMap(Appearance.init(rawValue:)) ?? .system
    }
}
#endif
