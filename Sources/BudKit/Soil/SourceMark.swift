import Foundation

/// How a planted bud stands with its source, as the device that keeps it live last saw it.
public struct SourceMark: Hashable, Codable, Sendable {
    public enum Status: Hashable, Codable, Sendable {
        /// Nothing new at the source.
        case live
        /// A field the source owns changed there: "moved", "renamed", "reopened".
        case changed(String)
        /// Done at the source: a closed issue, a merged pull request, an unflagged email.
        case closed
        /// A cancelled event.
        case cancelled
        /// Deleted at the source, or no longer readable; the bud keeps its last values.
        case gone
    }

    public var status: Status
    /// When the status came: a change shows for a day after it.
    public var at: Date?
    /// The last sync of the account, and the device that ran it.
    public var synced: Date?
    public var device: String?
    /// Where "Open in …" goes.
    public var url: URL?

    public init(status: Status = .live, at: Date? = nil, synced: Date? = nil, device: String? = nil, url: URL? = nil) {
        self.status = status
        self.at = at
        self.synced = synced
        self.device = device
        self.url = url
    }
}

/// The words of a planted bud's source row, on its card and at the top of its page.
public enum SourceRowText {
    /// How long a change stays on the card.
    public static let changedFor: TimeInterval = 24 * 3600

    /// The kind and item id in a `from` key: `linear:BUD-77` is Linear's BUD-77. Nil kind for one
    /// Bud does not know.
    public static func origin(_ from: String) -> (kind: SourceKind?, id: String) {
        guard let colon = from.firstIndex(of: ":") else { return (nil, from) }
        return (SourceKind(rawValue: String(from[..<colon])), String(from[from.index(after: colon)...]))
    }

    /// The source's name: Mail, Calendar, GitHub, Linear, or the key's own prefix.
    public static func name(_ from: String) -> String {
        if let kind = origin(from).kind { return kind.name }
        return from.split(separator: ":").first.map(String.init) ?? from
    }

    /// The status a card shows now: a change older than a day is live again.
    public static func status(_ mark: SourceMark?, now: Date) -> SourceMark.Status {
        guard let mark else { return .live }
        if case .changed = mark.status, let at = mark.at, now.timeIntervalSince(at) >= changedFor { return .live }
        return mark.status
    }

    /// The card's row: "Linear · live", "Calendar · moved 1h ago", "Calendar · cancelled at
    /// source", "GitHub · closed at source", "Mail · gone from source".
    public static func card(from: String, mark: SourceMark?, now: Date) -> String {
        let source = name(from)
        switch status(mark, now: now) {
        case .live: return "\(source) · live"
        case .changed(let what):
            guard let at = mark?.at else { return "\(source) · \(what)" }
            return "\(source) · \(what) \(ago(at, now: now))"
        case .closed: return "\(source) · closed at source"
        case .cancelled: return "\(source) · cancelled at source"
        case .gone: return "\(source) · gone from source"
        }
    }

    /// The page's first line: "From Linear · BUD-77".
    public static func title(from: String) -> String {
        "From \(name(from)) · \(origin(from).id)"
    }

    /// The page's second line: "Synced 5 min ago on Mac", or "Not synced yet".
    public static func synced(_ mark: SourceMark?, now: Date) -> String {
        guard let synced = mark?.synced else { return "Not synced yet" }
        let when = ago(synced, now: now)
        guard let device = mark?.device else { return "Synced \(when)" }
        return "Synced \(when) on \(device)"
    }

    /// "Open in Linear".
    public static func open(from: String) -> String { "Open in \(name(from))" }

    /// The page fields a source owns, which carry "from <source>": the title always, then
    /// State for mail, GitHub and Linear, When for a calendar, Due for Linear.
    public static func owns(_ field: Field, from: String) -> Bool {
        guard let kind = origin(from).kind else { return false }
        switch field {
        case .title: return true
        case .state: return kind != .calendar
        case .when: return kind == .calendar
        case .due: return kind == .linear
        }
    }

    public enum Field: Sendable { case title, state, when, due }

    /// "just now", "5 min ago", "1h ago", "3d ago".
    public static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86_400))d ago"
    }
}
