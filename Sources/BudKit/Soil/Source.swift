import Foundation

/// The kinds of source Bud reads. The raw value starts the `from` key a planted bud carries.
public enum SourceKind: String, CaseIterable, Codable, Sendable {
    case mail, calendar, github, linear

    /// The name the soil shows when the account has none of its own.
    public var name: String {
        switch self {
        case .mail: return "Mail"
        case .calendar: return "Calendar"
        case .github: return "GitHub"
        case .linear: return "Linear"
        }
    }

    /// The `from` key of an item of this kind, as in `mail:M1234`.
    public func key(_ id: String) -> String { "\(rawValue):\(id)" }
}

/// One thing a source shows below the soil: an email, an event, an issue. Nothing about it is
/// written to the vault until it is planted.
public struct SourceItem: Hashable, Codable, Sendable, Identifiable {
    /// What the source calls it.
    public var id: String
    public var title: String
    /// The second line: a sender, a time, a repository.
    public var detail: String?
    /// Mail: when it came. Calendar: when it starts. Linear: when it is due. GitHub: last update.
    public var date: Date?
    /// Mail only.
    public var unread: Bool
    /// GitHub only.
    public var role: Role?
    /// Linear only: 1 urgent to 4 low; nil for none.
    public var priority: Int?
    /// Whether it plants as a to-do: flagged mail, issues, pull requests.
    public var todo: Bool
    public var url: URL?

    /// Why a GitHub item is in front of you, most pressing first.
    public enum Role: Int, Codable, Sendable, Comparable {
        case reviewRequest, assigned, mine

        public static func < (a: Role, b: Role) -> Bool { a.rawValue < b.rawValue }
    }

    public init(
        id: String, title: String, detail: String? = nil, date: Date? = nil, unread: Bool = false,
        role: Role? = nil, priority: Int? = nil, todo: Bool = false, url: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.date = date
        self.unread = unread
        self.role = role
        self.priority = priority
        self.todo = todo
        self.url = url
    }
}

/// A connected account, read live on this device. The list of accounts syncs; the token that
/// reads one stays in this device's Keychain, so another device sees the account locked.
public struct SourceAccount: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var kind: SourceKind
    /// What the soil and the toast call it: "Work mail", "Home calendar".
    public var name: String
    /// True when this device holds no token for it.
    public var locked: Bool
    public var items: [SourceItem]

    public init(id: String, kind: SourceKind, name: String? = nil, locked: Bool = false, items: [SourceItem] = []) {
        self.id = id
        self.kind = kind
        self.name = name ?? kind.name
        self.locked = locked
        self.items = items
    }
}
