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

/// The Files view on a phone: the tree above the page with a handle between, or a sidebar that
/// slides in from the left. A flag while the two are tried on a device.
public enum PhoneFilesLayout: String, CaseIterable, Sendable {
    case split = "Split"
    case sidebar = "Sidebar"
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
        static let phoneFilesLayout = "bud.try.phoneFilesLayout"
    }

    private let defaults: UserDefaults

    @Published public var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    @Published public var phoneFilesLayout: PhoneFilesLayout {
        didSet { defaults.set(phoneFilesLayout.rawValue, forKey: Key.phoneFilesLayout) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Key.appearance).flatMap(Appearance.init(rawValue:)) ?? .system
        phoneFilesLayout = defaults.string(forKey: Key.phoneFilesLayout).flatMap(PhoneFilesLayout.init(rawValue:)) ?? .split
    }
}
#endif
