import Foundation
import BudKit

/// The vault on disk: BudKit's `Vault` over the Rust core, a folder of Markdown files with its
/// index kept apart (ADR-003). The core takes its own lock, so calls need no actor of their own.
///
/// The core's bindings are compiled into the app and share names with BudKit's types: here a bare
/// name is the core's and BudKit's carry their module.
final class RustVault: BudKit.Vault {
    let core: Vault

    /// Opens the vault at `paths`, making its folders when they are not there, and brings the
    /// index up to date with the files.
    init(paths: VaultPaths) throws {
        let files = FileManager.default
        try files.createDirectory(at: paths.vaultFolder, withIntermediateDirectories: true)
        try files.createDirectory(at: paths.indexFolder, withIntermediateDirectories: true)
        core = try openVault(vaultDir: paths.vaultFolder.path, indexPath: paths.indexFile.path)
    }

    var inboxPath: String { "Inbox" }
    var warehousePath: String { "Warehouse" }

    /// A bud that is only a folder gets its file on its first edit.
    func pathAfterEdit(_ path: String) -> String { path.hasSuffix(".md") ? path : path + ".md" }

    func snapshot() async throws -> [BudKit.BudRecord] {
        try core.snapshot().map(Self.record)
    }

    func create(parent: String?, title: String, kind: BudKit.BudKind, source: String?, preferredPath: String?) async throws -> String {
        try core.create(parent: parent, title: title, kind: kind == .todo ? .todo : .note, source: source)
    }

    func plant(parent: String?, title: String, kind: BudKit.BudKind, from: String, preferredPath: String?) async throws -> Planting {
        let planted = try core.plant(parent: parent, title: title, kind: kind == .todo ? .todo : .note, from: from)
        return Planting(path: planted.path, new: planted.new)
    }

    func setBody(_ path: String, _ text: String) async throws { try core.setBody(path: path, text: text) }

    func setState(_ path: String, _ state: BudKit.BudState?) async throws {
        try core.setState(path: path, state: state.map(Self.state))
    }

    func setWhen(_ path: String, _ when: Date?) async throws { try core.setWhen(path: path, when: when.map(Self.day)) }
    func setDue(_ path: String, _ due: Date?) async throws { try core.setDue(path: path, due: due.map(Self.day)) }
    func setPinned(_ path: String, _ pinned: Bool) async throws { try core.setPinned(path: path, pinned: pinned) }
    func setFromState(_ path: String, _ state: String?) async throws { try core.setFromState(path: path, state: state) }

    func shared(_ map: SharedMap) async throws -> [String: String] {
        let entries: [SharedEntry]
        switch map {
        case .sources: entries = try core.sources()
        case .leases: entries = try core.leases()
        case .triggers: entries = try core.triggers()
        }
        return Dictionary(entries.map { ($0.key, $0.value) }, uniquingKeysWith: { a, _ in a })
    }

    func setShared(_ map: SharedMap, _ key: String, _ value: String?) async throws {
        switch map {
        case .sources: try core.setSource(id: key, settings: value)
        case .leases: try core.setLease(id: key, lease: value)
        case .triggers: try core.setTrigger(id: key, trigger: value)
        }
    }
    func rename(_ path: String, to title: String) async throws -> String { try core.rename(path: path, newTitle: title) }
    func move(_ path: String, to parent: String?) async throws -> String { try core.moveTo(path: path, newParent: parent) }

    /// The files keep their own order until the vault can store one.
    func reorder(_ paths: [String], under parent: String?) async throws {}

    func trash(_ path: String) async throws -> String {
        try core.trash(path: path)
        return ".trash/" + path
    }

    func restore(_ path: String) async throws -> String { try core.restore(path: path) }
    func emptyTrash() async throws { try core.emptyTrash() }
    func deleteForever(_ path: String) async throws { try core.deleteForever(path: path) }

    /// Trashes everything, empties the Trash, and plants the records again, parents first.
    /// Empties the Trash first, so trashing a bud cannot meet a name the Trash already holds.
    func reset(to records: [BudKit.BudRecord]) async throws -> [String: String] {
        try core.emptyTrash()
        for bud in try core.snapshot() where bud.parent == nil && bud.place != .trash {
            try core.trash(path: bud.path)
        }
        try core.emptyTrash()
        return plant(records)
    }

    /// Writes records as new files, parents first, the Trash left out. A bud the Inbox held,
    /// whether a capture or under one, stays in the Inbox. A bud that will not plant is left out
    /// and what was under it goes to the top level, so one bad title loses one bud. Returns the
    /// path each planted bud has now, by its record's path.
    @discardableResult
    func plant(_ records: [BudKit.BudRecord]) -> [String: String] {
        var planted: [String: String] = [:]
        for record in records where record.place != .trash {
            let inInbox = record.parent == nil ? record.place == .inbox : record.parent == inboxID.uuidString
            let inWarehouse = record.parent == nil ? record.place == .warehouse : record.parent == warehouseID.uuidString
            let parent = inInbox ? inboxPath : inWarehouse ? warehousePath : record.parent.flatMap { planted[$0] }
            do {
                let path = try core.create(
                    parent: parent, title: record.title, kind: record.kind == .todo ? .todo : .note, source: record.source
                )
                planted[record.path] = path
                if let state = record.state { try core.setState(path: path, state: Self.state(state)) }
                if let when = record.when { try core.setWhen(path: path, when: Self.day(when)) }
                if let due = record.due { try core.setDue(path: path, due: Self.day(due)) }
                if record.pinned { try core.setPinned(path: path, pinned: true) }
                if let created = record.created {
                    try core.setCreated(path: path, created: ISO8601DateFormatter().string(from: created))
                }
                if !record.body.isEmpty { try core.setBody(path: path, text: record.body) }
            } catch {
                NSLog("Bud: \(record.title) did not plant: \(error)")
            }
        }
        return planted
    }

    func search(_ query: String, limit: Int) async throws -> [BudKit.HitRecord] {
        try core.search(query: query, limit: UInt64(max(limit, 0))).map {
            BudKit.HitRecord(path: $0.path, title: $0.title, trail: $0.trail, snippet: $0.snippet)
        }
    }

    func today(_ date: Date) async throws -> [BudKit.RowRecord] {
        try core.today(date: Self.day(date)).map(Self.row)
    }

    func counts(_ path: String) async throws -> BudKit.CountsRecord {
        let counts = try core.counts(path: path)
        return BudKit.CountsRecord(inside: Int(counts.inside), openTodos: Int(counts.openTodos))
    }

    func nextStep(under: String?, date: Date) async throws -> BudKit.RowRecord? {
        try core.nextStep(under: under, date: Self.day(date)).map(Self.row)
    }

    func addTag(_ path: String, _ tag: String) async throws { try core.addTag(path: path, tag: tag) }
    func removeTag(_ path: String, _ tag: String) async throws -> BudKit.TagEditRecord? {
        try core.removeTag(path: path, tag: tag).map { BudKit.TagEditRecord(path: $0.path, before: $0.before, after: $0.after) }
    }

    func renameTag(_ from: String, to: String) async throws -> [BudKit.TagEditRecord] {
        try core.renameTag(from: from, to: to).map { BudKit.TagEditRecord(path: $0.path, before: $0.before, after: $0.after) }
    }

    func restoreText(_ path: String, from expected: String, to text: String) async throws -> Bool {
        try core.restoreText(path: path, expected: expected, text: text)
    }

    func watch(_ onChange: @escaping @Sendable () -> Void) async throws -> BudKit.VaultWatch {
        let watch = try core.watch(listener: Listener(onChange: onChange))
        return BudKit.VaultWatch { watch.stop() }
    }

    /// Hears the core's file watcher and tells the store once per batch.
    private final class Listener: VaultListener {
        let onChange: @Sendable () -> Void
        init(onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }
        func changed(paths: [String]) { onChange() }
    }

    // MARK: Records

    private static func record(_ bud: BudRecord) -> BudKit.BudRecord {
        BudKit.BudRecord(
            path: bud.path, parent: bud.parent, title: bud.title, kind: bud.kind == .todo ? .todo : .note,
            state: bud.state.map { $0 == .done ? .done : .open }, when: bud.when.flatMap(date), due: bud.due.flatMap(date),
            pinned: bud.pinned, created: bud.created.flatMap(date), source: bud.source, from: bud.from, fromState: bud.fromState, body: bud.body,
            place: place(bud.place), tags: bud.tags
        )
    }

    private static func row(_ row: RowRecord) -> BudKit.RowRecord {
        BudKit.RowRecord(bud: record(row.bud), trail: row.trail)
    }

    private static func place(_ place: BudPlace) -> BudKit.BudPlace {
        switch place {
        case .everything: return .everything
        case .inbox: return .inbox
        case .archive: return .archive
        case .warehouse: return .warehouse
        case .trash: return .trash
        }
    }

    private static func state(_ state: BudKit.BudState) -> BudState {
        state == .done ? .done : .open
    }

    /// A day as the files write it, `2026-11-04`, in the device's calendar.
    private static func day(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// A date from the files: a day (`2026-11-04`, midnight in the device's calendar) or a moment
    /// (`2026-10-02T11:00:00Z`).
    private static func date(_ text: String) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        if text.count == 10, parts.count == 3 {
            return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }
        return ISO8601DateFormatter().date(from: text)
    }
}
