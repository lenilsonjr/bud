import Foundation

/// One account's column below the soil: what needs you soonest nearest the soil line, at most
/// three items, then how many more wait below.
public struct Root: Hashable, Sendable, Identifiable {
    public static let shown = 3

    public let account: SourceAccount
    /// Nearest the soil first.
    public let items: [SourceItem]
    /// The "N more below" row; zero shows none.
    public let more: Int
    /// The strip's leaf dot: the item right under the soil line needs you now.
    public let leaf: Bool

    public var id: String { account.id }
    /// Everything the account shows, for the strip chip.
    public var count: Int { items.count + more }

    /// A locked root shows nothing but its lock.
    public init(_ account: SourceAccount, now: Date = Date()) {
        self.account = account
        guard !account.locked else {
            items = []
            more = 0
            leaf = false
            return
        }
        let ordered = Self.order(account.items, kind: account.kind, now: now)
        items = Array(ordered.prefix(Self.shown))
        more = max(0, ordered.count - Self.shown)
        leaf = ordered.first.map { Self.needsYou($0, kind: account.kind, now: now) } ?? false
    }

    /// Soonest first. Mail: unread, then newest. Calendar: the next event, then what has passed,
    /// latest first. GitHub: review requests, then assigned issues, then your own pull requests,
    /// newest first in each. Linear: due date, then priority, undated and unprioritized last.
    public static func order(_ items: [SourceItem], kind: SourceKind, now: Date) -> [SourceItem] {
        let distant = Date.distantPast
        return items.sorted { a, b in
            switch kind {
            case .mail:
                if a.unread != b.unread { return a.unread }
                if a.date != b.date { return (a.date ?? distant) > (b.date ?? distant) }
            case .calendar:
                let ahead = (a.date ?? distant) >= now, bAhead = (b.date ?? distant) >= now
                if ahead != bAhead { return ahead }
                if a.date != b.date {
                    return ahead ? (a.date ?? distant) < (b.date ?? distant) : (a.date ?? distant) > (b.date ?? distant)
                }
            case .github:
                let ra = a.role ?? .mine, rb = b.role ?? .mine
                if ra != rb { return ra < rb }
                if a.date != b.date { return (a.date ?? distant) > (b.date ?? distant) }
            case .linear:
                if a.date != b.date {
                    guard let da = a.date else { return false }
                    guard let db = b.date else { return true }
                    return da < db
                }
                let pa = rank(a.priority), pb = rank(b.priority)
                if pa != pb { return pa < pb }
            }
            return a.id < b.id
        }
    }

    /// Linear's 0 means no priority; it sorts after 4.
    private static func rank(_ priority: Int?) -> Int {
        guard let priority, priority > 0 else { return Int.max }
        return priority
    }

    /// Whether an item wants you now: unread mail, an event within the hour, a review request,
    /// an issue due within a day or urgent.
    public static func needsYou(_ item: SourceItem, kind: SourceKind, now: Date) -> Bool {
        switch kind {
        case .mail: return item.unread
        case .calendar:
            guard let date = item.date else { return false }
            return date >= now && date.timeIntervalSince(now) <= 3600
        case .github: return item.role == .reviewRequest
        case .linear:
            if item.priority == 1 { return true }
            guard let date = item.date else { return false }
            return date.timeIntervalSince(now) <= 86_400
        }
    }
}
