import Foundation
#if canImport(Combine)
import Combine
#endif

/// The keys on this device: the table's defaults with the person's changes over them, kept in
/// `UserDefaults` under one key so they survive a relaunch and stay on the device they were
/// recorded on. The recorder's decisions live here too, so a test can press keys without a view:
/// a row starts recording, the next key lands or is refused, Esc cancels, a key another row holds
/// waits as a conflict until one of the two changes.
///
/// The keys the Mac answers to from the desktop are kept by their place on the keyboard as well,
/// under a second key, since the app registers them by code: the row shows the character the
/// layout in use gives that code. Such a row records on the Mac alone, and the app says when the
/// system refused its key, which the row shows as taken.
public final class KeyLayout {
    static let key = "bud.keys"
    static let hotKeysKey = "bud.hotkeys"

    /// Whether this device answers to keys from the desktop: the Mac does.
    public static var isDesktop: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

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

    /// A key a row wants that another row holds. Both rows show it. A row the Mac answers to
    /// from the desktop wants the key by its place on the keyboard too.
    public struct Conflict: Equatable, Sendable {
        public let id: Command.ID
        public let key: Key
        public let holder: Command.ID
        public var hotKey: PhysicalKey? = nil
    }

    private let defaults: UserDefaults
    private let desktop: Bool

    /// The keys recorded over the defaults, by row. A row recorded back to its default has none.
    public private(set) var overrides: [Command.ID: Key] {
        didSet { defaults.set(try? JSONEncoder().encode(Self.stored(overrides)), forKey: Self.key) }
    }
    /// Where the recorded keys of the rows the Mac answers to from the desktop sit on the
    /// keyboard. Such a row has one whenever it has an override, and the other way round.
    public private(set) var hotKeys: [Command.ID: PhysicalKey] = [:] {
        didSet { defaults.set(try? JSONEncoder().encode(Self.stored(hotKeys)), forKey: Self.hotKeysKey) }
    }
    /// The rows whose key the system refused to register: another app or the system itself
    /// answers to it already. The app says so after each registration.
    public private(set) var takenBySystem: Set<Command.ID> = []
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
    /// type, a key another row answers to. Such a row just shows its default. A row the Mac
    /// answers to from the desktop reads its key from where it sits on the keyboard, as the
    /// layout in use names it.
    public init(defaults: UserDefaults = .standard, desktop: Bool = KeyLayout.isDesktop) {
        self.defaults = defaults
        self.desktop = desktop
        overrides = Self.read([String: Key].self, defaults.data(forKey: Self.key))
        let kept = desktop ? Self.read([String: PhysicalKey].self, defaults.data(forKey: Self.hotKeysKey)) : [:]
        for id in Command.systemWide {
            overrides[id] = nil
            guard let hotKey = kept[id], hotKey != PhysicalKey(Command.of(id).key), let key = hotKey.key() else { continue }
            hotKeys[id] = hotKey
            overrides[id] = key
        }
        for command in Command.all {
            guard let key = overrides[command.id] else { continue }
            if key == command.key || !canRecord(command.id) || Self.types(key, in: command) || holder(of: key, besides: command.id) != nil {
                overrides[command.id] = nil
                self.hotKeys[command.id] = nil
            }
        }
    }

    /// The key a row answers to: the one recorded over it, else the table's. A row the Mac
    /// answers to from the desktop reads it off the keyboard in use, so the character follows
    /// the input source while the key under the finger stays.
    public func key(for id: Command.ID) -> Key {
        if let hotKey = hotKeys[id], let key = hotKey.key() { return key }
        return overrides[id] ?? Command.of(id).key
    }

    /// Where the key a row the Mac answers to from the desktop sits on the keyboard: the one
    /// recorded, else the table's default on the US keyboard. Nil for a row of the window.
    public func hotKey(for id: Command.ID) -> PhysicalKey? {
        guard Command.systemWide.contains(id) else { return nil }
        return hotKeys[id] ?? PhysicalKey(Command.of(id).key)
    }

    /// Whether the system refused the key a row the Mac answers to from the desktop holds.
    public func isTakenBySystem(_ id: Command.ID) -> Bool { takenBySystem.contains(id) }

    /// The app's word on a registration: the row shows its key as taken while the system keeps
    /// it, and plain again once a registration goes through.
    public func markTakenBySystem(_ id: Command.ID, _ taken: Bool) {
        guard takenBySystem.contains(id) != taken else { return }
        willChange()
        if taken { takenBySystem.insert(id) } else { takenBySystem.remove(id) }
    }

    /// Says the keys changed without any having been recorded: the input source did, so the
    /// rows the Mac answers to from the desktop read differently.
    public func refresh() { willChange() }

    public func isChanged(_ id: Command.ID) -> Bool { overrides[id] != nil }

    /// How many rows answer to a recorded key.
    public var changed: Int { overrides.count }

    /// Whether a row's key can be recorded here: the keys the Mac answers to from the desktop
    /// are the Mac's to record, and the other devices only show them.
    public func canRecord(_ id: Command.ID) -> Bool { desktop || !Command.systemWide.contains(id) }

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
    /// moves off it. `code` is where the key sits on the keyboard, which a row the Mac answers
    /// to from the desktop keeps and the others ignore; such a row refuses a key without one.
    @discardableResult
    public func record(_ key: Key?, at code: UInt16? = nil) -> Outcome {
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
        var hotKey: PhysicalKey?
        if Command.systemWide.contains(id) {
            guard let code else {
                refusal = .unnamed
                return .refused
            }
            hotKey = PhysicalKey(code: code, modifiers: key.modifiers)
        }
        recording = nil
        return land(key, on: id, at: hotKey)
    }

    /// Puts the default back on a row, and lets go of the key it wanted. A default a changed row
    /// holds now is a conflict like any other.
    public func reset(_ id: Command.ID) {
        willChange()
        land(Command.of(id).key, on: id, at: nil)
    }

    public func resetAll() {
        willChange()
        recording = nil
        refusal = nil
        conflicts = [:]
        overrides = [:]
        hotKeys = [:]
        takenBySystem = []
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
    private func land(_ key: Key, on id: Command.ID, at hotKey: PhysicalKey?) -> Outcome {
        let outcome: Outcome
        conflicts[id] = nil
        if let holder = holder(of: key, besides: id) {
            conflicts[id] = Conflict(id: id, key: key, holder: holder, hotKey: hotKey)
            outcome = .taken(by: holder)
        } else {
            set(key, for: id, at: hotKey)
            outcome = .bound
        }
        for command in Command.all {
            guard let waiting = conflicts[command.id] else { continue }
            if let holder = holder(of: waiting.key, besides: command.id) {
                conflicts[command.id] = Conflict(id: command.id, key: waiting.key, holder: holder, hotKey: waiting.hotKey)
            } else {
                conflicts[command.id] = nil
                set(waiting.key, for: command.id, at: waiting.hotKey)
            }
        }
        return outcome
    }

    /// Makes a row answer to a key; its default is no change at all. A row the Mac answers to
    /// from the desktop keeps where the key sits as well, and lets go of it with the default; its
    /// new key is not taken until the app says so.
    private func set(_ key: Key, for id: Command.ID, at hotKey: PhysicalKey?) {
        let command = Command.of(id)
        overrides[id] = key == command.key ? nil : key
        guard Command.systemWide.contains(id) else { return }
        hotKeys[id] = key == command.key || hotKey == PhysicalKey(command.key) ? nil : hotKey
        takenBySystem.remove(id)
    }

    private func willChange() {
        #if canImport(Combine)
        objectWillChange.send()
        #endif
    }

    /// The overrides keyed by the row's name, since a dictionary keyed by an enum encodes as a list.
    private static func stored<Value>(_ overrides: [Command.ID: Value]) -> [String: Value] {
        Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, $0.value) })
    }

    /// What was kept, by row; a row no longer in the table is dropped, and nothing readable is
    /// nothing kept.
    private static func read<Value: Decodable>(_ type: [String: Value].Type, _ data: Data?) -> [Command.ID: Value] {
        let stored = (try? JSONDecoder().decode(type, from: data ?? Data())) ?? [:]
        return Dictionary(uniqueKeysWithValues: stored.compactMap { name, value in Command.ID(rawValue: name).map { ($0, value) } })
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
