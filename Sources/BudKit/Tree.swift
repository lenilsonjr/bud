import Foundation

/// The one noun. A bud is text with a parent; what it *is* comes from what it carries:
/// no state → a note, a state → a to-do. Depth is unlimited and costs the same everywhere.
public let rootID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

/// The Inbox place: where a capture lands until it is given a home. Not a bud and not under the
/// root, so the canvas, the lenses and the tree never see what is in it.
public let inboxID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
/// The Library's Warehouse: templates, each a bud with what is inside it, copied into a place
/// when stamped.
public let warehouseID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

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
    /// The source item a planted bud came from, as in `mail:M1234`: its frontmatter `from`. Nil for
    /// a bud made here.
    public var from: String?
    /// How a planted bud stands with its source, as the device that keeps it live last saw it:
    /// its frontmatter `from-state`, as in `moved 2026-11-05T21:00:00Z`. Nil while nothing happened.
    public var fromState: String?
    /// The tags in the bud's own list (its frontmatter `tags`). The `#tags` in its body are read
    /// from the body: see `allTags`.
    public var tags: [String]

    public init(
        id: UUID = UUID(), text: String, state: BudState? = nil, parent: UUID = rootID, order: Double = 0,
        body: String = "", when: Date? = nil, due: Date? = nil, pinned: Bool = false, created: Date = Date(),
        source: String? = nil, from: String? = nil, fromState: String? = nil, tags: [String] = []
    ) {
        self.source = source
        self.from = from
        self.fromState = fromState
        self.tags = tags
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
        from = try c.decodeIfPresent(String.self, forKey: .from)
        fromState = try c.decodeIfPresent(String.self, forKey: .fromState)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
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

/// A branch in the Trash: the buds as they were, the head first, and when it went there. It
/// keeps its ids, parents and order so a restore puts it back exactly.
public struct TrashedBranch: Codable, Equatable, Sendable, Identifiable {
    public let at: Date
    public let buds: [Bud]

    public init(at: Date, buds: [Bud]) {
        self.at = at
        self.buds = buds
    }

    /// The bud the branch hangs from: the one whose parent is not in the branch.
    public var head: Bud { buds.first { bud in !buds.contains { $0.id == bud.parent } } ?? buds[0] }
    public var id: UUID { head.id }
    public var inside: Int { buds.count - 1 }
}

/// A plain value: every operation is a small mutation, so the store can persist after each one.
public struct Tree: Codable, Equatable, Sendable {
    public var buds: [Bud]
    /// What was trashed and not yet restored or deleted, oldest first.
    public var trashed: [TrashedBranch]

    public init(buds: [Bud] = [], trashed: [TrashedBranch] = []) {
        self.buds = buds
        self.trashed = trashed
    }

    /// Files saved before the Trash existed still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        buds = try c.decode([Bud].self, forKey: .buds)
        trashed = try c.decodeIfPresent([TrashedBranch].self, forKey: .trashed) ?? []
    }

    public func bud(_ id: UUID) -> Bud? {
        buds.first { $0.id == id }
    }

    public func children(of id: UUID) -> [Bud] {
        buds.filter { $0.parent == id }.sorted(by: Self.siblingOrder)
    }

    /// Siblings by their order, then by id so a tie reads the same everywhere.
    private static func siblingOrder(_ a: Bud, _ b: Bud) -> Bool {
        (a.order, a.id.uuidString) < (b.order, b.id.uuidString)
    }

    /// Every bud's children in their order, in one pass over the tree: what a walk reads, so it
    /// does not filter the whole tree at every step.
    private func childIndex() -> [UUID: [Bud]] {
        var index = Dictionary(grouping: buds, by: \.parent)
        for (parent, kids) in index { index[parent] = kids.sorted(by: Self.siblingOrder) }
        return index
    }

    public func hasChildren(_ id: UUID) -> Bool {
        buds.contains { $0.parent == id }
    }

    /// nil for the root; the root for first-layer buds.
    public func parent(of id: UUID) -> UUID? {
        id == rootID || id == inboxID || id == warehouseID ? nil : (bud(id)?.parent ?? rootID)
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
        if id == warehouseID { return "Warehouse" }
        return bud(id)?.text ?? ""
    }

    public func descendants(of id: UUID) -> [UUID] {
        let index = childIndex()
        var out: [UUID] = []
        var stack = (index[id] ?? []).map(\.id)
        var seen: Set<UUID> = [id]
        while let next = stack.popLast() {
            guard seen.insert(next).inserted else { continue }
            out.append(next)
            stack.append(contentsOf: (index[next] ?? []).map(\.id))
        }
        return out
    }

    public func openCount(under id: UUID) -> Int {
        let open = Set(buds.filter { $0.state == .open }.map(\.id))
        return descendants(of: id).filter(open.contains).count
    }

    /// The open to-dos among a bud's own children: the count beside "n inside", so it never
    /// tops it.
    public func openChildren(of id: UUID) -> Int {
        children(of: id).filter { $0.state == .open }.count
    }

    /// Descendants in reading order: each bud before its children, siblings in their order.
    public func walk(under id: UUID) -> [Bud] {
        let index = childIndex()
        var out: [Bud] = []
        // Each bud before its children: a stack of the siblings still to read, last first.
        var stack = Array((index[id] ?? []).reversed())
        var seen: Set<UUID> = [id]
        while let bud = stack.popLast() {
            guard seen.insert(bud.id).inserted else { continue }
            out.append(bud)
            stack.append(contentsOf: (index[bud.id] ?? []).reversed())
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

    /// What a bud's body says after its lede, the paragraphs an outline page shows under it.
    public func afterLede(of id: UUID) -> String {
        guard let body = bud(id)?.body else { return "" }
        var paragraphs = body.components(separatedBy: "\n\n")
        while let first = paragraphs.first, first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { paragraphs.removeFirst() }
        guard !paragraphs.isEmpty else { return "" }
        paragraphs.removeFirst()
        return paragraphs.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
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
    public mutating func add(_ text: String, todo: Bool, under parent: UUID, id: UUID = UUID()) -> Bud {
        let last = children(of: parent).last?.order ?? 0
        let bud = Bud(id: id, text: text, state: todo ? .open : nil, parent: parent, order: last + 1)
        buds.append(bud)
        return bud
    }

    /// Trades the places of two siblings. False, and nothing changes, when they are the same bud
    /// or do not share a parent.
    @discardableResult
    public mutating func swap(_ a: UUID, _ b: UUID) -> Bool {
        guard a != b, let first = bud(a), let second = bud(b), first.parent == second.parent else { return false }
        var ids = children(of: first.parent).map(\.id)
        guard let i = ids.firstIndex(of: a), let j = ids.firstIndex(of: b) else { return false }
        ids.swapAt(i, j)
        reorder(ids, under: first.parent)
        return true
    }

    /// The sibling `offset` places away in the order: -1 the one before, 1 the one after. Nil at
    /// either end, and for the root and the Inbox.
    public func sibling(of id: UUID, offset: Int) -> UUID? {
        guard let parent = bud(id)?.parent else { return nil }
        let ids = children(of: parent).map(\.id)
        guard let i = ids.firstIndex(of: id), ids.indices.contains(i + offset) else { return nil }
        return ids[i + offset]
    }

    /// Sets the order of a parent's children to the order of `ids`; children not named keep
    /// their places after them.
    public mutating func reorder(_ ids: [UUID], under parent: UUID) {
        let rest = children(of: parent).map(\.id).filter { !ids.contains($0) }
        for (index, id) in (ids + rest).enumerated() {
            guard let i = buds.firstIndex(where: { $0.id == id }), buds[i].parent == parent else { continue }
            buds[i].order = Double(index + 1)
        }
    }

    /// Capture: one line, no place in mind. It lands in the Inbox as a note, after the last.
    @discardableResult
    public mutating func capture(_ line: String, source: String, created: Date = Date(), id: UUID = UUID()) -> Bud {
        let last = children(of: inboxID).last?.order ?? 0
        let bud = Bud(id: id, text: line, parent: inboxID, order: last + 1, created: created, source: source)
        buds.append(bud)
        return bud
    }

    /// A source item planted under a parent, the Inbox included, as a bud carrying its `from`
    /// key, after the parent's last child.
    @discardableResult
    public mutating func plant(_ text: String, todo: Bool, under parent: UUID, from key: String, id: UUID = UUID()) -> Bud {
        var bud = add(text, todo: todo, under: parent, id: id)
        bud.from = key
        buds[buds.count - 1] = bud
        return bud
    }

    /// `tpl/Weekly review/2026-11-09T09:00Z`: the template and the minute it was stamped for, in UTC.
    public static func stampKey(_ template: String, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // UTC, so two devices in different zones name one occurrence alike.
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        return "tpl/\(template)/\(formatter.string(from: date))"
    }

    /// The templates in the Warehouse, in their order.
    public func templates() -> [Bud] { children(of: warehouseID) }

    /// The bud a source item was planted as, outside the Trash.
    public func planted(from key: String) -> Bud? {
        buds.first { $0.from == key }
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
        guard parent == rootID || parent == inboxID || parent == warehouseID || bud(parent) != nil else { return false }
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

    /// Trashes a bud and its whole branch: it moves to the Trash and is handed back, so it can be
    /// restored as it was: same ids, same parents, same order. Empty when the bud is unknown.
    @discardableResult
    public mutating func trash(_ id: UUID, at now: Date = Date()) -> [Bud] {
        guard bud(id) != nil else { return [] }
        let gone = Set(descendants(of: id) + [id])
        let branch = [bud(id)!] + buds.filter { gone.contains($0.id) && $0.id != id }
        buds.removeAll { gone.contains($0.id) }
        trashed.append(TrashedBranch(at: now, buds: branch))
        return branch
    }

    /// Puts a branch back and takes it out of the Trash. A bud whose id is already in the tree is
    /// skipped; a bud whose parent is gone lands under Everything, after the last thread.
    public mutating func restore(_ branch: [Bud]) {
        let present = Set(buds.map(\.id))
        let ids = Set(branch.map(\.id))
        trashed.removeAll { ids.contains($0.id) }
        var next = (children(of: rootID).last?.order ?? 0) + 1
        for var bud in branch where !present.contains(bud.id) {
            let parentKnown = [rootID, inboxID, warehouseID].contains(bud.parent) || ids.contains(bud.parent) || self.bud(bud.parent) != nil
            if !parentKnown {
                bud.parent = rootID
                bud.order = next
                next += 1
            }
            buds.append(bud)
        }
    }

    /// Restores the branch in the Trash that hangs from this bud; nothing when it is not there.
    public mutating func restore(_ id: UUID) {
        guard let branch = trashed.first(where: { $0.id == id }) else { return }
        restore(branch.buds)
    }

    /// Drops a branch from the Trash for good.
    public mutating func deleteForever(_ id: UUID) {
        trashed.removeAll { $0.id == id }
    }

    public mutating func emptyTrash() {
        trashed.removeAll()
    }

    /// Finished chapters: the threads under Everything that are closed, in their order.
    public func archived() -> [Bud] {
        children(of: rootID).filter(\.isDone)
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
