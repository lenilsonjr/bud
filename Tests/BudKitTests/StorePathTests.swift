#if canImport(SwiftUI)
import XCTest
@testable import BudKit

/// A vault that names buds the way a folder of Markdown files does: `Title.md`, children in the
/// folder beside it, a bud that is only a folder gets its file on its first edit, and the Trash
/// keeps a bud at `.trash/<where it was>`, under folders of its own like the core's.
private actor FolderVault: Vault {
    private var records: [BudRecord] = []

    nonisolated var inboxPath: String { "Inbox" }

    func snapshot() async throws -> [BudRecord] { records }

    private func index(_ path: String) throws -> Int {
        guard let i = records.firstIndex(where: { $0.path == path }) else { throw VaultError.notFound(path) }
        return i
    }

    private func folder(_ path: String) -> String { String(path.dropLast(3)) }

    func create(parent: String?, title: String, kind: BudKind, source: String?, preferredPath: String?) async throws -> String {
        let inbox = parent == inboxPath
        let home = inbox ? parent : parent.map(folder)
        let path = (home.map { $0 + "/" } ?? "") + title + ".md"
        records.append(BudRecord(
            path: path, parent: inbox ? nil : parent, title: title, kind: kind,
            state: kind == .todo ? .open : nil, source: source, place: inbox ? .inbox : .everything
        ))
        return path
    }

    /// Moves a bud to `new` and every bud in its folder with it.
    private func relocate(_ old: String, _ new: String, place: BudPlace? = nil) {
        let from = folder(old) + "/", to = folder(new) + "/"
        func moved(_ path: String?) -> String? {
            guard let path else { return nil }
            if path == old { return new }
            return path.hasPrefix(from) ? to + path.dropFirst(from.count) : path
        }
        for i in records.indices where records[i].path == old || records[i].path.hasPrefix(from) {
            records[i].path = moved(records[i].path)!
            if records[i].path != new { records[i].parent = moved(records[i].parent) }
            if let place { records[i].place = place }
        }
    }

    func rename(_ path: String, to title: String) async throws -> String {
        _ = try index(path)
        let up = path.split(separator: "/").dropLast().joined(separator: "/")
        let new = (up.isEmpty ? "" : up + "/") + title + ".md"
        relocate(path, new)
        records[records.firstIndex { $0.path == new }!].title = title
        return new
    }

    func move(_ path: String, to parent: String?) async throws -> String {
        let i = try index(path)
        let new = (parent.map { folder($0) + "/" } ?? "") + records[i].title + ".md"
        relocate(path, new)
        records[records.firstIndex { $0.path == new }!].parent = parent
        return new
    }

    func trash(_ path: String) async throws -> String {
        _ = try index(path)
        let new = ".trash/" + path
        let dirs = new.split(separator: "/").dropLast()
        var folder: String?
        for depth in 1..<max(dirs.count, 1) {
            let made = dirs.prefix(depth + 1).joined(separator: "/")
            if !records.contains(where: { $0.path == made }) {
                records.append(BudRecord(path: made, parent: folder, title: String(dirs[depth]), place: .trash))
            }
            folder = made
        }
        relocate(path, new, place: .trash)
        records[try index(new)].parent = folder
        return new
    }

    func restore(_ path: String) async throws -> String {
        _ = try index(path)
        let new = String(path.dropFirst(".trash/".count))
        relocate(path, new, place: .everything)
        let up = new.split(separator: "/").dropLast().joined(separator: "/")
        let hasFile = records.contains { $0.path == up + ".md" }
        let i = try index(new)
        records[i].parent = up.isEmpty ? nil : (hasFile ? up + ".md" : up)
        let parents = Set(records.compactMap(\.parent))
        records.removeAll { $0.place == .trash && !$0.path.hasSuffix(".md") && !parents.contains($0.path) }
        return new
    }

    nonisolated func pathAfterEdit(_ path: String) -> String { path.hasSuffix(".md") ? path : path + ".md" }

    /// A bud that is only a folder gets its file, and its children name it by it.
    private func file(_ path: String) throws -> Int {
        let i = try index(path)
        guard !path.hasSuffix(".md") else { return i }
        records[i].path = path + ".md"
        for j in records.indices where records[j].parent == path { records[j].parent = path + ".md" }
        return i
    }

    func plant(parent: String?, title: String, kind: BudKind, from: String, preferredPath: String?) async throws -> Planting {
        if let found = records.first(where: { $0.from == from && $0.place != .trash }) { return Planting(path: found.path, new: false) }
        let path = try await create(parent: parent, title: title, kind: kind, source: nil, preferredPath: nil)
        records[try file(path)].from = from
        return Planting(path: path, new: true)
    }

    func setBody(_ path: String, _ text: String) async throws { records[try file(path)].body = text }
    func setState(_ path: String, _ state: BudState?) async throws {
        let i = try file(path)
        records[i].state = state
        records[i].kind = state == nil ? .note : .todo
    }
    func setWhen(_ path: String, _ when: Date?) async throws { records[try file(path)].when = when }
    func setDue(_ path: String, _ due: Date?) async throws { records[try file(path)].due = due }
    func setPinned(_ path: String, _ pinned: Bool) async throws { records[try file(path)].pinned = pinned }
    func setFromState(_ path: String, _ state: String?) async throws { records[try file(path)].fromState = state }
    func reorder(_ paths: [String], under parent: String?) async throws {}
    func emptyTrash() async throws { records.removeAll { $0.place == .trash } }
    func deleteForever(_ path: String) async throws {
        let inside = folder(path) + "/"
        records.removeAll { $0.path == path || $0.path.hasPrefix(inside) }
    }
    /// Plants the records under paths of its own, `Title.md` by title, like a vault on disk.
    func reset(to records: [BudRecord]) async throws -> [String: String] {
        self.records = []
        var planted: [String: String] = [:]
        for record in records where record.place != .trash {
            let parent = record.place == .inbox && record.parent == nil ? inboxPath : record.parent.flatMap { planted[$0] }
            planted[record.path] = try await create(
                parent: parent, title: record.title, kind: record.kind, source: record.source, preferredPath: nil
            )
        }
        return planted
    }

    /// Puts records in as they are, for a vault that was there before the app.
    func put(_ records: [BudRecord]) { self.records = records }
    func search(_ query: String, limit: Int) async throws -> [HitRecord] { [] }
    func today(_ date: Date) async throws -> [RowRecord] { [] }
    func counts(_ path: String) async throws -> CountsRecord { CountsRecord(inside: 0, openTodos: 0) }
    func nextStep(under: String?, date: Date) async throws -> RowRecord? { nil }
    func watch(_ onChange: @escaping @Sendable () -> Void) async throws -> VaultWatch { VaultWatch {} }
    func addTag(_ path: String, _ tag: String) async throws { records[try index(path)].tags.append(tag) }
    func removeTag(_ path: String, _ tag: String) async throws -> TagEditRecord? {
        records[try index(path)].tags.removeAll { $0 == tag }
        return nil
    }
    func renameTag(_ from: String, to: String) async throws -> [TagEditRecord] { [] }
    func restoreText(_ path: String, from expected: String, to text: String) async throws -> Bool { false }

    func paths() -> [String] { records.map(\.path) }
}

/// The store over a vault that names buds by their files: a bud keeps its id, and the center
/// stays on it, while renames and moves give it new paths.
@MainActor
final class StorePathTests: XCTestCase {
    private func planted() async throws -> (BudStore, FolderVault, kitchen: UUID, shelf: UUID) {
        let vault = FolderVault()
        let store = BudStore(vault: vault, tree: Tree())
        await store.reload()
        let kitchen = try XCTUnwrap(store.add("Kitchen", todo: false, under: rootID)).id
        let shelf = try XCTUnwrap(store.add("Shelf", todo: true, under: kitchen)).id
        store.setBody(shelf, "Two boards")
        await store.settle()
        return (store, vault, kitchen, shelf)
    }

    func testPlantingWritesFilesAndKeepsTheIds() async throws {
        let (store, vault, kitchen, shelf) = try await planted()
        let paths = await vault.paths()
        XCTAssertEqual(paths, ["Kitchen.md", "Kitchen/Shelf.md"])
        XCTAssertEqual(store.tree.bud(shelf)?.parent, kitchen)
        XCTAssertEqual(store.tree.bud(shelf)?.body, "Two boards", "the body found the bud's file")
    }

    func testARenameKeepsTheCenterAndTheBranch() async throws {
        let (store, vault, kitchen, shelf) = try await planted()
        store.center = kitchen
        store.update(kitchen, text: "Pantry", todo: false)
        store.toggle(shelf)
        await store.settle()
        let paths = await vault.paths()
        XCTAssertEqual(paths, ["Pantry.md", "Pantry/Shelf.md"])
        XCTAssertEqual(store.center, kitchen)
        XCTAssertEqual(store.tree.bud(kitchen)?.text, "Pantry")
        XCTAssertEqual(store.tree.bud(shelf)?.state, .done, "a write after the rename finds the new path")
    }

    func testTrashAndUndoBringTheSameBudsBack() async throws {
        let (store, vault, kitchen, shelf) = try await planted()
        store.trash(kitchen)
        await store.settle()
        let trashed = await vault.paths()
        XCTAssertEqual(trashed, [".trash/Kitchen.md", ".trash/Kitchen/Shelf.md"])
        store.toasts.current?.action.undo?()
        for _ in 0..<5 { await Task.yield() }
        await store.settle()
        let paths = await vault.paths()
        XCTAssertEqual(paths, ["Kitchen.md", "Kitchen/Shelf.md"])
        XCTAssertEqual(store.tree.bud(shelf)?.parent, kitchen)
    }

    func testABudTrashedFromALiveParentRestoresFromTheTrashPage() async throws {
        let (store, vault, kitchen, shelf) = try await planted()
        store.trash(shelf)
        await store.settle()
        let trashed = await vault.paths()
        XCTAssertEqual(Set(trashed), ["Kitchen.md", ".trash/Kitchen", ".trash/Kitchen/Shelf.md"], "the core's folder is there")
        XCTAssertEqual(store.tree.trashed.map(\.id), [shelf], "its folder is not a branch of its own")
        store.restore(shelf)
        await store.settle()
        let paths = await vault.paths()
        XCTAssertEqual(paths, ["Kitchen.md", "Kitchen/Shelf.md"])
        XCTAssertEqual(store.tree.bud(shelf)?.parent, kitchen)
        XCTAssertTrue(store.tree.trashed.isEmpty)
    }

    func testEditingAFolderOnlyBudFollowsItToItsFile() async throws {
        let vault = FolderVault()
        await vault.put([
            BudRecord(path: "Trips", title: "Trips"),
            BudRecord(path: "Trips/Rome.md", parent: "Trips", title: "Rome"),
        ])
        let store = BudStore(vault: vault, tree: Tree())
        await store.reload()
        let trips = try XCTUnwrap(store.tree.children(of: rootID).first).id
        store.center = trips
        store.setBody(trips, "Summer")
        store.setPinned(trips, true)
        await store.settle()
        let paths = await vault.paths()
        XCTAssertEqual(paths, ["Trips.md", "Trips/Rome.md"])
        XCTAssertEqual(store.center, trips, "the bud kept its id")
        XCTAssertEqual(store.tree.bud(trips)?.body, "Summer")
        XCTAssertEqual(store.tree.bud(trips)?.pinned, true, "the write after the first found the file")
        XCTAssertEqual(store.tree.children(of: trips).map(\.text), ["Rome"])
    }

    func testAFreshStartFindsTheSampleBudsWhereTheVaultPutThem() async throws {
        let (store, vault, _, _) = try await planted()
        store.freshStart(sample: true)
        let first = try XCTUnwrap(store.tree.children(of: rootID).first)
        store.setBody(first.id, "Fresh")
        await store.settle()
        let records = try await vault.snapshot()
        XCTAssertEqual(records.first { $0.path == first.text + ".md" }?.body, "Fresh")
        XCTAssertEqual(store.tree.bud(first.id)?.body, "Fresh", "the seed bud kept its id")
    }

    func testACaptureLandsInTheInboxFolder() async throws {
        let (store, vault, _, _) = try await planted()
        let line = try XCTUnwrap(store.capture("Call the plumber", source: "iphone"))
        store.makeTodo(line.id)
        await store.settle()
        let paths = await vault.paths()
        XCTAssertTrue(paths.contains("Inbox/Call the plumber.md"))
        XCTAssertEqual(store.tree.bud(line.id)?.state, .open)
        XCTAssertEqual(store.tree.bud(line.id)?.parent, inboxID)
    }
}
#endif
