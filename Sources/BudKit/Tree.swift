import Foundation

/// The one noun. A bud is text with a parent; what it *is* comes from what it carries:
/// no state → a note, a state → a to-do. Depth is unlimited and costs the same everywhere.
public let rootID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

/// The Inbox place: where a capture lands until it is given a home. Not a bud and not under the
/// root, so the canvas, the lenses and the tree never see what is in it.
public let inboxID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

public enum BudState: String, Codable, Sendable {
    case open, done
}

public struct Bud: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var text: String
    public var state: BudState?
    public var parent: UUID
    public var order: Double
    /// The Markdown below the title. Empty for most buds.
    public var body: String
    /// The day it is scheduled for, and the day it is due: the frontmatter keys of the same names.
    public var when: Date?
    public var due: Date?
    public var pinned: Bool
    public var created: Date
    /// Where a capture came from: "mac", "ipad", "iphone" or "tv". Nil for ordinary buds.
    public var source: String?

    public init(
        id: UUID = UUID(), text: String, state: BudState? = nil, parent: UUID = rootID, order: Double = 0,
        body: String = "", when: Date? = nil, due: Date? = nil, pinned: Bool = false, created: Date = Date(),
        source: String? = nil
    ) {
        self.source = source
        self.id = id
        self.text = text
        self.state = state
        self.parent = parent
        self.order = order
        self.body = body
        self.when = when
        self.due = due
        self.pinned = pinned
        self.created = created
    }

    /// Files saved before these properties existed still load: each one has a default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        state = try c.decodeIfPresent(BudState.self, forKey: .state)
        parent = try c.decode(UUID.self, forKey: .parent)
        order = try c.decode(Double.self, forKey: .order)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        when = try c.decodeIfPresent(Date.self, forKey: .when)
        due = try c.decodeIfPresent(Date.self, forKey: .due)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        source = try c.decodeIfPresent(String.self, forKey: .source)
    }

    public var isTodo: Bool { state != nil }
    public var isDone: Bool { state == .done }

    /// The word on the status tag: To-do, Done or Note.
    public var statusLabel: String {
        switch state {
        case .open: return "To-do"
        case .done: return "Done"
        case nil: return "Note"
        }
    }
}

/// A plain value: every operation is a small mutation, so the store can persist after each one.
public struct Tree: Codable, Equatable, Sendable {
    public var buds: [Bud]

    public init(buds: [Bud] = []) {
        self.buds = buds
    }

    public func bud(_ id: UUID) -> Bud? {
        buds.first { $0.id == id }
    }

    public func children(of id: UUID) -> [Bud] {
        buds.filter { $0.parent == id }.sorted { ($0.order, $0.id.uuidString) < ($1.order, $1.id.uuidString) }
    }

    public func hasChildren(_ id: UUID) -> Bool {
        buds.contains { $0.parent == id }
    }

    /// nil for the root; the root for first-layer buds.
    public func parent(of id: UUID) -> UUID? {
        id == rootID || id == inboxID ? nil : (bud(id)?.parent ?? rootID)
    }

    /// Nearest first, root last.
    public func ancestors(of id: UUID) -> [UUID] {
        var out: [UUID] = []
        var seen: Set<UUID> = [id]
        var cursor = parent(of: id)
        while let p = cursor, !seen.contains(p) {
            out.append(p)
            seen.insert(p)
            cursor = parent(of: p)
        }
        return out
    }

    public func title(of id: UUID) -> String {
        if id == rootID { return "Everything" }
        if id == inboxID { return "Inbox" }
        return bud(id)?.text ?? ""
    }

    public func descendants(of id: UUID) -> [UUID] {
        var out: [UUID] = []
        var stack = children(of: id).map(\.id)
        while let next = stack.popLast() {
            out.append(next)
            stack.append(contentsOf: children(of: next).map(\.id))
        }
        return out
    }

    public func openCount(under id: UUID) -> Int {
        descendants(of: id).compactMap(bud).filter { $0.state == .open }.count
    }

    /// Descendants in reading order: each bud before its children, siblings in their order.
    public func walk(under id: UUID) -> [Bud] {
        var out: [Bud] = []
        for child in children(of: id) {
            out.append(child)
            out.append(contentsOf: walk(under: child.id))
        }
        return out
    }

    /// The one open to-do to do next under a bud: the soonest due, then the soonest scheduled,
    /// then the oldest; reading order breaks the remaining ties. Nil when nothing is open.
    public func nextStep(under id: UUID) -> Bud? {
        let open = walk(under: id).filter { $0.state == .open }
        guard var best = open.first else { return nil }
        for bud in open.dropFirst() where Tree.comesFirst(bud, before: best) { best = bud }
        return best
    }

    /// Whether `a` is the sooner step: a date beats no date, an earlier date beats a later one.
    static func comesFirst(_ a: Bud, before b: Bud) -> Bool {
        func sooner(_ x: Date?, _ y: Date?) -> Bool? {
            switch (x, y) {
            case let (x?, y?): return x == y ? nil : x < y
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return nil
            }
        }
        if let byDue = sooner(a.due, b.due) { return byDue }
        if let byWhen = sooner(a.when, b.when) { return byWhen }
        return a.created < b.created
    }

    /// One row of the outline: a bud and how deep it sits under the root.
    public struct OutlineRow: Hashable, Sendable {
        public let id: UUID
        public let depth: Int
    }

    /// The rows an outline shows: every bud under `root` whose ancestors are all expanded, in
    /// reading order, with its depth. The root itself is not a row.
    public func outline(under root: UUID = rootID, expanded: Set<UUID>) -> [OutlineRow] {
        var rows: [OutlineRow] = []
        func visit(_ id: UUID, depth: Int) {
            for child in children(of: id) {
                rows.append(OutlineRow(id: child.id, depth: depth))
                if expanded.contains(child.id) { visit(child.id, depth: depth + 1) }
            }
        }
        visit(root, depth: 0)
        return rows
    }

    /// The first paragraph of a bud's body, the lede its page shows; empty when there is none.
    public func lede(of id: UUID) -> String {
        guard let body = bud(id)?.body else { return "" }
        return body.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    /// Today: open to-dos due on or before the day (overdue first), and buds scheduled for the
    /// day or earlier. A bud that is both due and scheduled shows once, under Due.
    public func today(on day: Date = Date(), calendar: Calendar = .current) -> (due: [Bud], scheduled: [Bud]) {
        let end = calendar.startOfDay(for: day).addingTimeInterval(86_400)
        let all = walk(under: rootID)
        let due = all.filter { $0.state == .open && ($0.due.map { $0 < end } ?? false) }
            .sorted { ($0.due!, $0.text) < ($1.due!, $1.text) }
        let dueIDs = Set(due.map(\.id))
        let scheduled = all.filter { !dueIDs.contains($0.id) && !$0.isDone && ($0.when.map { $0 < end } ?? false) }
            .sorted { ($0.when!, $0.text) < ($1.when!, $1.text) }
        return (due, scheduled)
    }

    /// Every open to-do, grouped by the top-level thread it sits under, threads in their order.
    public func openTodos() -> [(thread: Bud, todos: [Bud])] {
        children(of: rootID).compactMap { thread in
            let todos = ([thread] + walk(under: thread.id)).filter { $0.state == .open }
            return todos.isEmpty ? nil : (thread, todos)
        }
    }

    /// Every pinned bud, in reading order.
    public func pinned() -> [Bud] {
        walk(under: rootID).filter(\.pinned)
    }

    /// The file a bud would be on disk, as the document bar shows it:
    /// "Everything / Launch the newsletter / pick-a-name.md".
    public func filePath(of id: UUID) -> String {
        let folders = ([rootID] + ancestors(of: id).reversed().filter { $0 != rootID }).map { title(of: $0) }
        return (folders + [Tree.fileName(for: title(of: id))]).joined(separator: " / ")
    }

    /// A title as a file name: lowercase, words joined by dashes, nothing but letters and digits.
    public static func fileName(for title: String) -> String {
        let words = title.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        return (words.isEmpty ? "untitled" : words.joined(separator: "-")) + ".md"
    }

    /// The titles above a bud, root left out: "Launch the newsletter › Pick a name".
    public func breadcrumb(of id: UUID) -> [String] {
        ancestors(of: id).reversed().filter { $0 != rootID }.map { title(of: $0) }
    }

    /// The orbit a bud belongs to: its parent and every sibling, itself included. The root's
    /// orbit is the root alone.
    public func orbit(of id: UUID) -> Set<UUID> {
        guard let parent = parent(of: id) else { return [id] }
        return Set(children(of: parent).map(\.id)).union([parent, id])
    }

    /// A peek inside a bud: the first few titles under it, in reading order.
    public func peek(into id: UUID, limit: Int = 3) -> [String] {
        children(of: id).prefix(limit).map(\.text)
    }

    /// The kind a new bud starts as: a to-do under a to-do, a note under a note or the root.
    public func suggestsTodo(under parent: UUID) -> Bool {
        bud(parent)?.isTodo ?? false
    }

    @discardableResult
    public mutating func add(_ text: String, todo: Bool, under parent: UUID) -> Bud {
        let last = children(of: parent).last?.order ?? 0
        let bud = Bud(text: text, state: todo ? .open : nil, parent: parent, order: last + 1)
        buds.append(bud)
        return bud
    }

    /// Capture: one line, no place in mind. It lands in the Inbox as a note, after the last.
    @discardableResult
    public mutating func capture(_ line: String, source: String, created: Date = Date()) -> Bud {
        let last = children(of: inboxID).last?.order ?? 0
        let bud = Bud(text: line, parent: inboxID, order: last + 1, created: created, source: source)
        buds.append(bud)
        return bud
    }

    /// What waits in the Inbox, in reading order.
    public func inbox() -> [Bud] {
        children(of: inboxID)
    }

    /// Gives a bud and its whole branch a new parent, after the parent's last child. Refuses a
    /// move under itself or its own descendant, and an unknown bud or parent; true when it moved.
    @discardableResult
    public mutating func move(_ id: UUID, under parent: UUID) -> Bool {
        guard let i = buds.firstIndex(where: { $0.id == id }) else { return false }
        guard parent == rootID || parent == inboxID || bud(parent) != nil else { return false }
        guard parent != id, !descendants(of: id).contains(parent) else { return false }
        let last = children(of: parent).last?.order ?? 0
        buds[i].parent = parent
        buds[i].order = last + 1
        return true
    }

    public mutating func update(_ id: UUID, text: String, todo: Bool) {
        guard let i = buds.firstIndex(where: { $0.id == id }) else { return }
        buds[i].text = text
        if todo, buds[i].state == nil { buds[i].state = .open }
        if !todo { buds[i].state = nil }
    }

    public mutating func setBody(_ id: UUID, _ body: String) {
        guard let i = buds.firstIndex(where: { $0.id == id }) else { return }
        buds[i].body = body
    }

    public mutating func setWhen(_ id: UUID, _ when: Date?) {
        guard let i = buds.firstIndex(where: { $0.id == id }) else { return }
        buds[i].when = when
    }

    public mutating func setDue(_ id: UUID, _ due: Date?) {
        guard let i = buds.firstIndex(where: { $0.id == id }) else { return }
        buds[i].due = due
    }

    public mutating func setPinned(_ id: UUID, _ pinned: Bool) {
        guard let i = buds.firstIndex(where: { $0.id == id }) else { return }
        buds[i].pinned = pinned
    }

    public mutating func toggle(_ id: UUID) {
        guard let i = buds.firstIndex(where: { $0.id == id }), let state = buds[i].state else { return }
        buds[i].state = state == .done ? .open : .done
    }

    /// Closes an open to-do; with `cascade` every open to-do under it closes too, notes and done
    /// ones untouched. Returns the ids it changed, the bud first, so they can be reopened exactly.
    /// Closing never cascades on its own: the caller asks.
    @discardableResult
    public mutating func close(_ id: UUID, cascade: Bool) -> [UUID] {
        guard let i = buds.firstIndex(where: { $0.id == id }), buds[i].state == .open else { return [] }
        buds[i].state = .done
        var changed = [id]
        guard cascade else { return changed }
        for inside in descendants(of: id) {
            guard let j = buds.firstIndex(where: { $0.id == inside }), buds[j].state == .open else { continue }
            buds[j].state = .done
            changed.append(inside)
        }
        return changed
    }

    /// Sets closed to-dos back to open; anything else is left alone.
    public mutating func reopen(_ ids: [UUID]) {
        for id in ids {
            guard let i = buds.firstIndex(where: { $0.id == id }), buds[i].state == .done else { continue }
            buds[i].state = .open
        }
    }

    /// Removes a bud and its whole subtree.
    public mutating func remove(_ id: UUID) {
        let gone = Set(descendants(of: id) + [id])
        buds.removeAll { gone.contains($0.id) }
    }

    /// Trashes a bud and its whole branch and hands the branch back, so it can be restored as it
    /// was: same ids, same parents, same order. Empty when the bud is unknown.
    @discardableResult
    public mutating func trash(_ id: UUID) -> [Bud] {
        let gone = Set(descendants(of: id) + [id])
        let branch = buds.filter { gone.contains($0.id) }
        buds.removeAll { gone.contains($0.id) }
        return branch
    }

    /// Puts a trashed branch back. A bud whose id is already in the tree is skipped.
    public mutating func restore(_ branch: [Bud]) {
        let present = Set(buds.map(\.id))
        buds.append(contentsOf: branch.filter { !present.contains($0.id) })
    }

    /// A small world to start from.
    /// A small fictional world: a newsletter being launched, with a few bodies, two due dates,
    /// one scheduled day and one pinned bud, so every lens and picture has something to show.
    public static func seed() -> Tree {
        var t = Tree()
        let day: TimeInterval = 86_400
        let newsletter = t.add("Launch the newsletter", todo: true, under: rootID)
        t.setBody(newsletter.id, "A monthly letter for the garden club: one story, one tip, one date.\n\nFirst issue goes out when the name and the sender are settled.")
        t.setPinned(newsletter.id, true)
        let name = t.add("Pick a name", todo: true, under: newsletter.id)
        t.setDue(name.id, Date().addingTimeInterval(2 * day))
        t.add("Shortlist three candidates", todo: true, under: name.id)
        t.add("Ask two readers which one lands", todo: true, under: name.id)
        let short = t.add("Short names read better in the inbox", todo: false, under: name.id)
        t.setBody(short.id, "Most inboxes cut the sender name at about twenty characters.")
        let sender = t.add("Set up the sender", todo: true, under: newsletter.id)
        t.add("Domain records are in the shared doc", todo: false, under: sender.id)
        let verify = t.add("Verify the address", todo: true, under: sender.id)
        t.setDue(verify.id, Date().addingTimeInterval(-1 * day))
        let design = t.add("Design notes", todo: false, under: newsletter.id)
        t.add("Warm, not corporate", todo: false, under: design.id)
        t.add("First issue outline", todo: false, under: newsletter.id)
        let roadmap = t.add("Q4 roadmap", todo: true, under: rootID)
        t.add("Review the onboarding flow", todo: true, under: roadmap.id)
        t.add("Launch notes", todo: false, under: roadmap.id)
        let language = t.add("Learn a language", todo: true, under: rootID)
        t.add("Ten minutes a day", todo: true, under: language.id)
        let health = t.add("Health reset", todo: true, under: rootID)
        let walk = t.add("A walk before the first meeting", todo: true, under: health.id)
        t.setWhen(walk.id, Date())
        t.add("Routines", todo: false, under: rootID)
        t.add("Gift ideas", todo: false, under: rootID)
        t.add("Side project", todo: false, under: rootID)
        let printer = t.capture("Ask the printer about paper samples", source: "mac", created: Date().addingTimeInterval(-1 * day))
        t.add("Three paper weights to compare", todo: false, under: printer.id)
        t.capture("A recipe to try for the first issue", source: "iphone")
        return t
    }
}
