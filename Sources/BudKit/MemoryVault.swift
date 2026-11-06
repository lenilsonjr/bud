import Foundation

/// A vault over the in-memory `Tree`: for tests, previews, pictures and the seed world. With a
/// file it also keeps the tree as JSON after every change, which is how the app stores buds until
/// the Rust vault takes over. A bud's path is its id.
public actor MemoryVault: Vault {
    public private(set) var tree: Tree
    private let fileURL: URL?
    private var watchers: [UUID: @Sendable () -> Void] = [:]

    public init(tree: Tree = Tree.seed(), fileURL: URL? = nil) {
        self.tree = tree
        self.fileURL = fileURL
    }

    /// A vault over what the file holds, or over `fallback` when it is missing or unreadable.
    public init(contentsOf fileURL: URL, fallback: Tree = Tree.seed()) {
        let loaded = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(Tree.self, from: $0) }
        self.init(tree: loaded ?? fallback, fileURL: fileURL)
    }

    /// A change made outside the app, as the folder would see one: it edits the tree and tells
    /// every watcher once.
    public func externalChange(_ edit: (inout Tree) -> Void) {
        edit(&tree)
        save()
        for notify in watchers.values { notify() }
    }

    public func snapshot() async throws -> [BudRecord] {
        tree.records()
    }

    public func create(parent: String?, title: String, kind: BudKind, source: String?, preferredPath: String?) async throws -> String {
        let id = preferredPath.flatMap { UUID(uuidString: $0) } ?? UUID()
        guard tree.bud(id) == nil else { throw VaultError.refused("A bud is already at \(id.uuidString)") }
        let home = try parentID(parent)
        if home == inboxID, let source {
            tree.capture(title, source: source, id: id)
        } else {
            tree.add(title, todo: kind == .todo, under: home, id: id)
            if let source, let i = tree.buds.firstIndex(where: { $0.id == id }) { tree.buds[i].source = source }
        }
        save()
        return id.uuidString
    }

    public func plant(parent: String?, title: String, kind: BudKind, from: String, preferredPath: String?) async throws -> Planting {
        if let bud = tree.buds.first(where: { $0.from == from }) { return Planting(path: bud.path, new: false) }
        let path = try await create(parent: parent, title: title, kind: kind, source: nil, preferredPath: preferredPath)
        if let i = tree.buds.firstIndex(where: { $0.path == path }) { tree.buds[i].from = from }
        save()
        return Planting(path: path, new: true)
    }

    public func setBody(_ path: String, _ text: String) async throws {
        tree.setBody(try known(path), text)
        save()
    }

    public func setState(_ path: String, _ state: BudState?) async throws {
        let id = try known(path)
        guard let i = tree.buds.firstIndex(where: { $0.id == id }) else { throw VaultError.notFound(path) }
        tree.buds[i].state = state
        save()
    }

    public func setWhen(_ path: String, _ when: Date?) async throws {
        tree.setWhen(try known(path), when)
        save()
    }

    public func setDue(_ path: String, _ due: Date?) async throws {
        tree.setDue(try known(path), due)
        save()
    }

    private var maps: [SharedMap: [String: String]] = [:]

    public func shared(_ map: SharedMap) async throws -> [String: String] { maps[map] ?? [:] }

    public func setShared(_ map: SharedMap, _ key: String, _ value: String?) async throws {
        maps[map, default: [:]][key] = value
    }

    public func setFromState(_ path: String, _ state: String?) async throws {
        let id = try known(path)
        guard let i = tree.buds.firstIndex(where: { $0.id == id }) else { throw VaultError.notFound(path) }
        tree.buds[i].fromState = state
        save()
    }

    public func setPinned(_ path: String, _ pinned: Bool) async throws {
        tree.setPinned(try known(path), pinned)
        save()
    }

    public func rename(_ path: String, to title: String) async throws -> String {
        let id = try known(path)
        guard let i = tree.buds.firstIndex(where: { $0.id == id }) else { throw VaultError.notFound(path) }
        tree.buds[i].text = title
        save()
        return path
    }

    public func move(_ path: String, to parent: String?) async throws -> String {
        let id = try known(path)
        guard tree.move(id, under: try parentID(parent)) else { throw VaultError.refused("Cannot move \(path) there") }
        save()
        return path
    }

    /// A path the vault no longer knows, a bud deleted outside the app, is skipped rather than
    /// refusing the whole order.
    public func reorder(_ paths: [String], under parent: String?) async throws {
        let ids = paths.compactMap { try? known($0) }
        tree.reorder(ids, under: try parentID(parent))
        save()
    }

    public func trash(_ path: String) async throws -> String {
        let id = try known(path)
        tree.trash(id)
        save()
        return path
    }

    public func restore(_ path: String) async throws -> String {
        guard let id = UUID(uuidString: path), tree.trashed.contains(where: { $0.id == id }) else {
            throw VaultError.notFound(path)
        }
        tree.restore(id)
        save()
        return path
    }

    public func emptyTrash() async throws {
        tree.emptyTrash()
        save()
    }

    public func deleteForever(_ path: String) async throws {
        guard let id = UUID(uuidString: path), tree.trashed.contains(where: { $0.id == id }) else {
            throw VaultError.notFound(path)
        }
        tree.deleteForever(id)
        save()
    }

    public func reset(to records: [BudRecord]) async throws -> [String: String] {
        tree = Tree(records: records)
        save()
        return Dictionary(records.map { ($0.path, $0.path) }, uniquingKeysWith: { first, _ in first })
    }

    public func search(_ query: String, limit: Int) async throws -> [HitRecord] {
        TreeSearcher(tree: tree).search(query, limit: limit).map { hit in
            let snippet = tree.lede(of: hit.id)
            return HitRecord(path: hit.id.uuidString, title: hit.title, trail: hit.trail, snippet: snippet)
        }
    }

    public func today(_ date: Date) async throws -> [RowRecord] {
        let day = tree.today(on: date)
        return (day.due + day.scheduled).map(row)
    }

    public func counts(_ path: String) async throws -> CountsRecord {
        let id = try known(path)
        return CountsRecord(inside: tree.descendants(of: id).count, openTodos: tree.openCount(under: id))
    }

    public func nextStep(under: String?, date: Date) async throws -> RowRecord? {
        let root = try parentID(under)
        return tree.nextStep(under: root).map(row)
    }

    public func addTag(_ path: String, _ tag: String) async throws {
        guard BudTags.clean(tag) != nil else { throw VaultError.refused("Not a tag: \(tag)") }
        tree.addTag(try known(path), tag)
        save()
    }

    public func removeTag(_ path: String, _ tag: String) async throws -> TagEditRecord? {
        let id = try known(path)
        guard let old = tree.bud(id) else { return nil }
        tree.removeTag(id, tag)
        save()
        guard let new = tree.bud(id), new.tags != old.tags else { return nil }
        return TagEditRecord(path: id.uuidString, before: Self.text(of: old), after: Self.text(of: new))
    }

    /// A bud's text here is its list and body as JSON: the memory vault has no file to hand over.
    public func renameTag(_ from: String, to: String) async throws -> [TagEditRecord] {
        guard BudTags.clean(from) != nil, BudTags.clean(to) != nil else {
            throw VaultError.refused("Not a tag: \(from) or \(to)")
        }
        let before = tree
        let changed = tree.renameTag(from, to: to)
        save()
        return changed.compactMap { id in
            guard let old = before.bud(id), let new = tree.bud(id) else { return nil }
            return TagEditRecord(path: id.uuidString, before: Self.text(of: old), after: Self.text(of: new))
        }
    }

    public func restoreText(_ path: String, from expected: String, to text: String) async throws -> Bool {
        let id = try known(path)
        guard let now = tree.bud(id), Self.text(of: now) == expected else { return false }
        guard let data = text.data(using: .utf8), let written = try? JSONDecoder().decode(Written.self, from: data),
              let i = tree.buds.firstIndex(where: { $0.id == id }) else { throw VaultError.refused("Not a text from this vault") }
        tree.buds[i].tags = written.tags
        tree.buds[i].body = written.body
        save()
        return true
    }

    private struct Written: Codable {
        var tags: [String]
        var body: String
    }

    private static func text(of bud: Bud) -> String {
        // Sorted keys: the text is compared later, so the same bud must always give the same text.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(Written(tags: bud.tags, body: bud.body))) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    public func watch(_ onChange: @escaping @Sendable () -> Void) async throws -> VaultWatch {
        let key = UUID()
        watchers[key] = onChange
        return VaultWatch { [weak self] in
            guard let self else { return }
            Task { await self.stopWatching(key) }
        }
    }

    private func stopWatching(_ key: UUID) {
        watchers[key] = nil
    }

    private func row(_ bud: Bud) -> RowRecord {
        let trail = tree.ancestors(of: bud.id).reversed().map { tree.title(of: $0) }
        return RowRecord(bud: tree.record(of: bud, place: tree.place(of: bud.id)), trail: trail)
    }

    /// The bud a path names, which must be in the tree (not in the Trash).
    private func known(_ path: String) throws -> UUID {
        guard let id = UUID(uuidString: path), tree.bud(id) != nil else { throw VaultError.notFound(path) }
        return id
    }

    /// The parent a path names: nil is Everything; the Inbox, the Warehouse and every bud are themselves.
    private func parentID(_ path: String?) throws -> UUID {
        guard let path else { return rootID }
        guard let id = UUID(uuidString: path), [rootID, inboxID, warehouseID].contains(id) || tree.bud(id) != nil else {
            throw VaultError.notFound(path)
        }
        return id
    }

    private func save() {
        guard let url = fileURL, let data = try? JSONEncoder().encode(tree) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
