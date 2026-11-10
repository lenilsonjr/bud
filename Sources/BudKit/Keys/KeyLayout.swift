import Foundation
#if canImport(Combine)
import Combine
#endif

/// The keys on this device: the table's defaults with the person's changes over them, kept in
/// `UserDefaults` under one key so they survive a relaunch and stay on the device they were
/// recorded on. The recorder's decisions live here too, so a test can press keys without a view:
/// a row starts recording, the next key lands or is refused, Esc cancels, a key another row holds
/// waits as a conflict until one of the two changes.
public final class KeyLayout {
    static let key = "bud.keys"

    /// Where a recorded key landed.
    public enum Outcome: Equatable, Sendable {
        /// Esc: the row keeps its key.
        case cancelled
        /// The key cannot be the row's; `refusal` says why, and the row keeps recording.
        case refused
        /// Another row holds the key: nothing is saved until one of the two changes.
        case taken(by: Command.ID)
        /// The row answers to the key from now on.
        case bound
    }

    /// Why the last key pressed did not land.
    public enum Refusal: Equatable, Sendable {
        /// A bare key for a row that fires everywhere: it would swallow typing.
        case bare
        /// A key the table has no name for.
        case unnamed
    }

    /// A key a row wants that another row holds. Both rows show it.
    public struct Conflict: Equatable, Sendable {
        public let id: Command.ID
        public let key: Key
        public let holder: Command.ID
    }

    private let defaults: UserDefaults

    /// The keys recorded over the defaults, by row. A row recorded back to its default has none.
    public private(set) var overrides: [Command.ID: Key] {
        didSet { defaults.set(try? JSONEncoder().encode(Self.stored(overrides)), forKey: Self.key) }
    }
    /// The row whose keycap was clicked, waiting for a key.
    public private(set) var recording: Command.ID?
    /// Why the last key pressed was refused; the row says so until the next one.
    public private(set) var refusal: Refusal?
    /// The keys rows want that other rows hold, by the row that wants.
    public private(set) var conflicts: [Command.ID: Conflict] = [:]

    #if canImport(Combine)
    public let objectWillChange = ObservableObjectPublisher()
    #endif

    /// Reads the keys kept on this device, and lets go of any the table of today would refuse:
    /// one back on its default, one for a row that cannot record, a bare key where it would
    /// type, a key another row answers to. Such a row just shows its default.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let data = defaults.data(forKey: Self.key) ?? Data()
        let stored = (try? JSONDecoder().decode([String: Key].self, from: data)) ?? [:]
        overrides = Dictionary(uniqueKeysWithValues: stored.compactMap { name, key in Command.ID(rawValue: name).map { ($0, key) } })
        for command in Command.all {
            guard let key = overrides[command.id] else { continue }
            if key == command.key || !canRecord(command.id) || Self.types(key, in: command) || holder(of: key, besides: command.id) != nil {
                overrides[command.id] = nil
            }
        }
    }

    /// The key a row answers to: the one recorded over it, else the table's.
    public func key(for id: Command.ID) -> Key { overrides[id] ?? Command.of(id).key }

    public func isChanged(_ id: Command.ID) -> Bool { overrides[id] != nil }

    /// How many rows answer to a recorded key.
    public var changed: Int { overrides.count }

    /// Whether a row's key can be recorded: the keys the Mac answers to from the desktop are
    /// registered once at launch, so recording them comes later.
    public func canRecord(_ id: Command.ID) -> Bool { !Command.systemWide.contains(id) }

    /// The conflict a row is the holder of, if a row wants its key.
    public func wanted(_ id: Command.ID) -> Conflict? {
        Command.all.lazy.compactMap { self.conflicts[$0.id] }.first { $0.holder == id }
    }

    public func startRecording(_ id: Command.ID) {
        guard canRecord(id) else { return }
        willChange()
        recording = id
        refusal = nil
    }

    public func cancelRecording() {
        willChange()
        recording = nil
        refusal = nil
    }

    /// Lets go of the line a refused key put under the row, before the next key.
    public func clearRefusal() {
        guard refusal != nil else { return }
        willChange()
        refusal = nil
    }

    /// The next key for the row recording, nil for one the table cannot name, which is refused.
    /// The key the row has now, or its default, binds at once, the default dropping the change.
    /// Otherwise a bare Esc cancels, and a key with nothing beyond Shift on it is refused for a
    /// row that fires everywhere, since it would take a letter from every text field. A key
    /// another row would answer to as well is kept aside as a conflict and lands once that row
    /// moves off it.
    @discardableResult
    public func record(_ key: Key?) -> Outcome {
        guard let id = recording else { return .cancelled }
        willChange()
        refusal = nil
        guard let key else {
            refusal = .unnamed
            return .refused
        }
        let command = Command.of(id)
        if key == self.key(for: id) {
            recording = nil
            conflicts[id] = nil
            return .bound
        }
        if key != command.key {
            if key == Key(.escape) {
                recording = nil
                return .cancelled
            }
            if Self.types(key, in: command) {
                refusal = .bare
                return .refused
            }
        }
        recording = nil
        return land(key, on: id)
    }

    /// Puts the default back on a row, and lets go of the key it wanted. A default a changed row
    /// holds now is a conflict like any other.
    public func reset(_ id: Command.ID) {
        willChange()
        land(Command.of(id).key, on: id)
    }

    public func resetAll() {
        willChange()
        recording = nil
        refusal = nil
        conflicts = [:]
        overrides = [:]
    }

    /// The row that would answer to a key as well as `id`, if one would.
    public func holder(of key: Key, besides id: Command.ID) -> Command.ID? {
        let wanter = Command.of(id)
        return Command.all.first { $0.id != id && self.key(for: $0.id) == key && Self.clash(wanter, $0, over: key) }?.id
    }

    /// Whether a key would type in a text field instead of running a row that fires everywhere.
    private static func types(_ key: Key, in command: Command) -> Bool {
        !key.hasModifiers && command.scope == .everywhere
    }

    /// Whether two rows that share a key would both answer it: in the same scope always; across
    /// scopes when neither acts in place and one of them fires everywhere or the key is modified,
    /// since the menu bar answers a modified key before any surface sees it. A row that acts in
    /// place is a list's own, so Esc can close a list, go back on the canvas and read a page.
    private static func clash(_ a: Command, _ b: Command, over key: Key) -> Bool {
        if a.scope == b.scope { return true }
        guard !a.inPlace, !b.inPlace else { return false }
        return a.scope == .everywhere || b.scope == .everywhere || key.hasModifiers
    }

    /// Gives a row a key, as a conflict while another row holds it, in place of whatever the row
    /// wanted before, then lets every conflict whose holder moved off its key land.
    @discardableResult
    private func land(_ key: Key, on id: Command.ID) -> Outcome {
        let outcome: Outcome
        conflicts[id] = nil
        if let holder = holder(of: key, besides: id) {
            conflicts[id] = Conflict(id: id, key: key, holder: holder)
            outcome = .taken(by: holder)
        } else {
            set(key, for: id)
            outcome = .bound
        }
        for command in Command.all {
            guard let waiting = conflicts[command.id] else { continue }
            if let holder = holder(of: waiting.key, besides: command.id) {
                conflicts[command.id] = Conflict(id: command.id, key: waiting.key, holder: holder)
            } else {
                conflicts[command.id] = nil
                set(waiting.key, for: command.id)
            }
        }
        return outcome
    }

    /// Makes a row answer to a key; its default is no change at all.
    private func set(_ key: Key, for id: Command.ID) {
        overrides[id] = key == Command.of(id).key ? nil : key
    }

    private func willChange() {
        #if canImport(Combine)
        objectWillChange.send()
        #endif
    }

    /// The overrides keyed by the row's name, since a dictionary keyed by an enum encodes as a list.
    private static func stored(_ overrides: [Command.ID: Key]) -> [String: Key] {
        Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, $0.value) })
    }
}

#if canImport(Combine)
extension KeyLayout: ObservableObject {}
#endif

extension Key.Base {
    /// The base the way the layout keeps it: the letter itself, or the named key's name.
    var name: String {
        switch self {
        case .letter(let letter): return String(letter)
        case .space: return "space"
        case .escape: return "escape"
        case .return: return "return"
        case .tab: return "tab"
        case .upArrow: return "upArrow"
        case .downArrow: return "downArrow"
        }
    }

    init?(name: String) {
        switch name {
        case "space": self = .space
        case "escape": self = .escape
        case "return": self = .return
        case "tab": self = .tab
        case "upArrow": self = .upArrow
        case "downArrow": self = .downArrow
        default:
            guard name.count == 1, let letter = name.first else { return nil }
            self = .letter(letter)
        }
    }
}

extension Key: Codable {
    private enum CodingKeys: String, CodingKey {
        case base, modifiers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .base)
        guard let base = Base(name: name) else {
            throw DecodingError.dataCorruptedError(forKey: .base, in: container, debugDescription: "No key is named \(name)")
        }
        self.init(base, Modifiers(rawValue: try container.decode(UInt8.self, forKey: .modifiers)))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(base.name, forKey: .base)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
    }
}
