import Foundation

/// The pages of the Apple TV Files tab and the rows each one shows, kept pure so they test on
/// their own: the Inbox, Today, the open to-dos, the pinned buds and Everything's outline.
public enum TVFilesPage: String, CaseIterable, Hashable, Sendable {
    case inbox = "Inbox"
    case today = "Today"
    case todos = "Open to-dos"
    case pinned = "Pinned"
    case everything = "Everything"

    /// The SF Symbol beside the page's name, the ones the Mac sidebar uses.
    public var symbol: String {
        switch self {
        case .inbox: return "tray"
        case .today: return "sun.max"
        case .todos: return "checkmark.square"
        case .pinned: return "pin"
        case .everything: return "leaf.fill"
        }
    }

    /// The line under the page's title when it has no rows.
    public var empty: String {
        switch self {
        case .inbox: return "Nothing waiting. A capture lands here."
        case .today: return "Nothing due or scheduled for today."
        case .todos: return "Every to-do is closed."
        case .pinned: return "Nothing pinned yet. Pin a bud on the Mac or the iPhone."
        case .everything: return "Nothing planted yet. Capture the first bud."
        }
    }
}

/// One row of a TV Files page: the bud, the line under its title, and what a click does.
public struct TVFilesRow: Hashable, Sendable {
    public enum Tag: Hashable, Sendable {
        case none
        /// "Due 3 Nov" in pistil.
        case due(Date)
        /// "3 Nov" for a scheduled bud.
        case scheduled(Date)
        /// "3 inside · 1 open" for a bud with children.
        case inside(Int, open: Int)
    }

    public let id: UUID
    public let title: String
    public let caption: String
    public let tag: Tag
    public let isTodo: Bool
    public let isDone: Bool
    /// True when a click goes inside the bud instead of ticking it.
    public let opens: Bool
}

public enum TVFilesText {
    /// The count beside a page's name; nil where the Mac sidebar shows none.
    public static func count(_ page: TVFilesPage, in tree: Tree, on day: Date = Date()) -> Int? {
        switch page {
        case .inbox: return tree.inbox().count
        case .today:
            let today = tree.today(on: day)
            return today.due.count + today.scheduled.count
        case .todos: return tree.openTodos().reduce(0) { $0 + $1.todos.count }
        case .pinned: return tree.pinned().count
        case .everything: return nil
        }
    }

    /// The rows a page shows. Inside a bud, whichever page the walk began on, the rows are the
    /// bud's children with their kind under the title, since the trail above says where they are.
    public static func rows(_ page: TVFilesPage, in tree: Tree, inside: UUID = rootID, on day: Date = Date()) -> [TVFilesRow] {
        if inside != rootID {
            return tree.children(of: inside).map { row($0, in: tree, caption: kind($0)) }
        }
        switch page {
        case .inbox:
            return tree.inbox().map { row($0, in: tree, caption: "Captured \(Tree.dayLabel(for: $0.created, now: day).lowercased())") }
        case .today:
            let today = tree.today(on: day)
            return today.due.map { row($0, in: tree, tag: .due($0.due!)) }
                + today.scheduled.map { row($0, in: tree, tag: .scheduled($0.when!)) }
        case .todos:
            return tree.openTodos().flatMap { group in group.todos.map { row($0, in: tree) } }
        case .pinned:
            return tree.pinned().map { row($0, in: tree) }
        case .everything:
            return tree.children(of: inside).map { row($0, in: tree) }
        }
    }

    /// The titles above the buds on show inside Everything: "Launch the newsletter › Pick a name".
    public static func trail(inside id: UUID, in tree: Tree) -> [String] {
        guard id != rootID else { return [] }
        return tree.breadcrumb(of: id) + [tree.title(of: id)]
    }

    /// "Due 3 Nov", "Overdue · 2 Nov" once the day has passed, "3 Nov", "3 inside · 1 open".
    public static func label(_ tag: TVFilesRow.Tag, now: Date = Date(), calendar: Calendar = .current) -> String? {
        switch tag {
        case .none: return nil
        case let .due(date):
            return date < calendar.startOfDay(for: now) ? "Overdue · \(short(date))" : "Due \(short(date))"
        case let .scheduled(date): return short(date)
        case let .inside(count, open): return "\(count) inside" + (open > 0 ? " · \(open) open" : "")
        }
    }

    private static func short(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f.string(from: date)
    }

    /// One bud as a row with its trail under the title, for the hits of Go anywhere.
    public static func row(_ id: UUID, in tree: Tree) -> TVFilesRow? {
        tree.bud(id).map { row($0, in: tree) }
    }

    private static func kind(_ bud: Bud) -> String {
        bud.isTodo ? (bud.isDone ? "Done" : "To-do") : "Note"
    }

    private static func row(_ bud: Bud, in tree: Tree, caption: String? = nil, tag: TVFilesRow.Tag = .none) -> TVFilesRow {
        let kids = tree.children(of: bud.id)
        let crumbs = tree.breadcrumb(of: bud.id).filter { $0 != "Inbox" }
        let line = caption ?? (crumbs.isEmpty ? kind(bud) : crumbs.joined(separator: " › "))
        let finalTag: TVFilesRow.Tag
        if case .none = tag, !kids.isEmpty {
            finalTag = .inside(kids.count, open: tree.openCount(under: bud.id))
        } else {
            finalTag = tag
        }
        return TVFilesRow(
            id: bud.id, title: bud.text, caption: line, tag: finalTag,
            isTodo: bud.isTodo, isDone: bud.isDone, opens: !kids.isEmpty
        )
    }
}
