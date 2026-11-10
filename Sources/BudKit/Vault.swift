import Foundation

/// Whether a bud is a note or a to-do, as the vault's record says.
public enum BudKind: String, Codable, Sendable {
    case note, todo
}

/// Where a bud lives: Everything's tree, the Inbox, the Archive (a finished thread) or the Trash.
public enum BudPlace: String, Codable, Sendable {
    case everything, inbox, archive, warehouse, trash
}

/// One bud as a vault has it, flat. It mirrors the record the Rust bindings export, with dates
/// kept as `Date` so a round trip through the in-memory tree loses nothing.
public struct BudRecord: Codable, Hashable, Sendable {
    /// Where the bud is in the vault. The memory vault uses the bud's id.
    public var path: String
    /// The path of the bud above; nil for a top-level bud.
    public var parent: String?
    public var title: String
    public var kind: BudKind
    public var state: BudState?
    public var when: Date?
    public var due: Date?
    public var pinned: Bool
    public var created: Date?
    public var source: String?
    /// The source item a planted bud came from, as in `mail:M1234`.
    public var from: String?
    /// How a planted bud stands with its source, as in `moved 2026-11-05T21:00:00Z`.
    public var fromState: String?
    public var body: String
    public var place: BudPlace
    /// The tags in the bud's own list: its frontmatter `tags`, not the `#tags` in its body.
    public var tags: [String]

    public init(
        path: String, parent: String? = nil, title: String, kind: BudKind = .note, state: BudState? = nil,
        when: Date? = nil, due: Date? = nil, pinned: Bool = false, created: Date? = nil, source: String? = nil,
        from: String? = nil, fromState: String? = nil, body: String = "", place: BudPlace = .everything, tags: [String] = []
    ) {
        self.from = from
        self.fromState = fromState
        self.path = path
        self.parent = parent
        self.title = title
        self.kind = kind
        self.state = state
        self.when = when
        self.due = due
        self.pinned = pinned
        self.created = created
        self.source = source
        self.body = body
        self.place = place
        self.tags = tags
    }
}

/// Where a planted item went, and whether planting made that bud or found the one it made before.
public struct Planting: Hashable, Sendable {
    public var path: String
    public var new: Bool

    public init(path: String, new: Bool) {
        self.path = path
        self.new = new
    }
}

/// A bud with the titles above it, root first.
public struct RowRecord: Hashable, Sendable {
    public var bud: BudRecord
    public var trail: [String]

    public init(bud: BudRecord, trail: [String]) {
        self.bud = bud
        self.trail = trail
    }
}

/// A search result.
public struct HitRecord: Hashable, Sendable {
    public var path: String
    public var title: String
    public var trail: [String]
    public var snippet: String

    public init(path: String, title: String, trail: [String], snippet: String) {
        self.path = path
        self.title = title
        self.trail = trail
        self.snippet = snippet
    }
}

/// What is under a bud: every descendant, and the open to-dos among them.
public struct CountsRecord: Hashable, Sendable {
    public var inside: Int
    public var openTodos: Int

    public init(inside: Int, openTodos: Int) {
        self.inside = inside
        self.openTodos = openTodos
    }
}

public enum VaultError: Error, Equatable, Sendable {
    /// No bud at that path.
    case notFound(String)
    /// The vault refuses the change, such as a move under the bud's own branch.
    case refused(String)
}

/// What `watch` hands back; cancelling stops the callbacks.
public final class VaultWatch: @unchecked Sendable {
    private let stop: @Sendable () -> Void

    public init(stop: @escaping @Sendable () -> Void) { self.stop = stop }

    public func cancel() { stop() }
}

/// Where BudKit reads and writes buds. The app plugs in a vault; a view never touches a file.
/// Paths name buds; a vault that renames or moves a bud returns the new path.
public protocol Vault: Sendable {
    /// The path the Inbox goes by, as a parent.
    var inboxPath: String { get }
    /// Where templates are kept: the parent path of a bud at the top of the Warehouse.
    var warehousePath: String { get }
    /// The path a bud has after its body or a property is written: a vault on disk gives a bud
    /// that is only a folder a file of its own then.
    func pathAfterEdit(_ path: String) -> String

    /// Every bud, parents before children, siblings in their order, the Trash's buds last.
    func snapshot() async throws -> [BudRecord]

    /// Returns the new bud's path. A nil parent is the top level. `preferredPath` is the path the
    /// caller would like the bud to have; a vault that names its own buds may ignore it.
    func create(parent: String?, title: String, kind: BudKind, source: String?, preferredPath: String?) async throws -> String
    /// Plants a source item under `parent` (nil is the top level) as a bud carrying `from`, or
    /// finds the bud it was planted as before, outside the Trash. `preferredPath` is as in `create`.
    func plant(parent: String?, title: String, kind: BudKind, from: String, preferredPath: String?) async throws -> Planting
    func setBody(_ path: String, _ text: String) async throws
    /// The bud's file as the vault holds it, front matter and body: what the Source panel shows.
    /// A bud that is only a folder has no file yet, and no text.
    func text(_ path: String) async throws -> String
    /// A nil state makes the bud a note.
    func setState(_ path: String, _ state: BudState?) async throws
    func setWhen(_ path: String, _ when: Date?) async throws
    func setDue(_ path: String, _ due: Date?) async throws
    /// How a planted bud stands with its source; nil clears it.
    func setFromState(_ path: String, _ state: String?) async throws
    func setPinned(_ path: String, _ pinned: Bool) async throws
    /// Returns the new path.
    func rename(_ path: String, to title: String) async throws -> String
    /// Gives the bud and its branch a new parent, last among its children; nil is the top level.
    /// Returns the new path.
    func move(_ path: String, to parent: String?) async throws -> String
    /// Puts a parent's children in the order of `paths`; nil is the top level. A vault on disk
    /// keeps its own file order until it can store one.
    func reorder(_ paths: [String], under parent: String?) async throws
    /// Returns the path in the Trash.
    @discardableResult
    func trash(_ path: String) async throws -> String
    /// Returns the restored path.
    func restore(_ path: String) async throws -> String
    func emptyTrash() async throws
    func deleteForever(_ path: String) async throws
    /// Replaces everything, the Trash included, with these records: a fresh start, empty or seeded.
    /// Returns the path each record's bud has now, by the record's path.
    @discardableResult
    func reset(to records: [BudRecord]) async throws -> [String: String]

    func search(_ query: String, limit: Int) async throws -> [HitRecord]
    /// The open to-dos due on or before the day, and the buds scheduled for it.
    func today(_ date: Date) async throws -> [RowRecord]
    func counts(_ path: String) async throws -> CountsRecord
    /// The open to-do to do next under a bud, or anywhere when `under` is nil.
    func nextStep(under: String?, date: Date) async throws -> RowRecord?
    /// Adds a tag to a bud's own list. A bud that carries it already, in its list or as a `#tag`
    /// in its body, stays as it is.
    func addTag(_ path: String, _ tag: String) async throws
    /// Takes a tag out of a bud's own list. A `#tag` in its body stays: that is the bud's text.
    /// Returns the text it rewrote, for undo.
    func removeTag(_ path: String, _ tag: String) async throws -> TagEditRecord?
    /// Renames a tag in every bud outside the Trash, lists and bodies alike, with the tags nested
    /// under it; renaming onto a tag in use merges the two. Returns each bud it changed.
    func renameTag(_ from: String, to: String) async throws -> [TagEditRecord]
    /// Puts back the text a tag change handed over as `before`, while the bud still holds the
    /// change's `after`: an edit made since is never undone. Returns whether it wrote.
    func restoreText(_ path: String, from expected: String, to text: String) async throws -> Bool

    /// Calls back once per batch of changes made outside the app.
    func watch(_ onChange: @escaping @Sendable () -> Void) async throws -> VaultWatch

    /// Text the vault keeps beside the buds and syncs with them, by key: `sources` holds each
    /// connected source's settings (never a token), `leases` which device keeps an account's
    /// planted buds live, `layout` how the panels around a page are arranged, `board` which tag
    /// columns a bud's board shows, under the bud's id, `lenses` the lenses the person named
    /// and kept, under each lens's id.
    func shared(_ map: SharedMap) async throws -> [String: String]
    /// Nil removes the key.
    func setShared(_ map: SharedMap, _ key: String, _ value: String?) async throws

    /// The first picture the bud at `path` embeds, as the file holds it: what its board card
    /// shows. Nil when it embeds none, or the vault keeps no pictures.
    func picture(of path: String) async throws -> Data?
}

/// The maps a vault keeps beside the buds.
public enum SharedMap: String, Sendable {
    case sources, leases, triggers, layout, board, lenses
}

extension Vault {
    public var inboxPath: String { inboxID.uuidString }
    public var warehousePath: String { warehouseID.uuidString }
    public func pathAfterEdit(_ path: String) -> String { path }
    public func picture(of path: String) async throws -> Data? { nil }
}
