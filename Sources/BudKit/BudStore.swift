#if canImport(SwiftUI)
import Foundation
import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The two ways of looking at the same tree.
public enum Surface: String, CaseIterable, Sendable {
    case canvas = "Canvas"
    case files = "Files"
}

/// A query across every thread, shown as a page in Files.
public enum Lens: String, CaseIterable, Sendable {
    case today = "Today", todos = "To-dos", pinned = "Pinned"
}

/// A place that holds buds and has a page of its own in Files, beside Everything's tree: the
/// Inbox (captures), the Archive (finished chapters) and the Trash (recoverable branches).
public enum Place: String, CaseIterable, Sendable {
    case inbox = "Inbox", archive = "Archive", trash = "Trash"
}

/// The tree, the current center of the web, and the layout derived from both.
/// Every mutation goes to the vault and reloads from it; the layout is recomputed once per change, not per frame.
@MainActor
public final class BudStore: ObservableObject {
    @Published public private(set) var tree: Tree
    @Published public private(set) var layout: Layout
    @Published public var center: UUID {
        didSet {
            if center != oldValue {
                relayout()
                lens = nil
                place = nil
            }
        }
    }
    /// The place Files shows instead of the center's page; a change of center or lens clears it.
    @Published public var place: Place? = nil
    /// Whether Files shows the Inbox.
    public var inboxOpen: Bool {
        get { place == .inbox }
        set { place = newValue ? .inbox : nil }
    }
    @Published public var surface: Surface = .canvas
    /// The lens Files shows instead of the center's page; a change of center clears it.
    @Published public var lens: Lens? = nil {
        didSet { if lens != nil { place = nil } }
    }
    /// The question the canvas is asked: its hits stay lit and the rest fades. Nil for none.
    @Published public var canvasLens: LensQuery? = nil {
        didSet { if canvasLens != oldValue { relight() } }
    }
    /// How each bud stands under the canvas lens, worked out once per change of tree or lens.
    @Published public private(set) var canvasLight: [UUID: LensQuery.Match] = [:]
    /// The canvas scale: 1 is 100%. Pinch changes it; the zoom control in the bar resets it.
    @Published public var zoom: CGFloat = 1
    /// Whether Files shows its sidebar; follows the window shape until the bar button decides.
    @Published public var sidebar = SidebarVisibility()
    /// The size of the area below the bar, so the bar button knows what the toggle flips.
    /// Not published: it changes on every frame of a resize and nothing draws from it.
    public var surfaceSize: CGSize = .zero
    /// What the window shows over everything else; BudRootView draws it as a scrim and a card.
    @Published var modal: Modal? = nil
    /// The bud planted or captured last and when, so the canvas can give it an entry cue.
    @Published public private(set) var lastPlanted: Planted? = nil

    public struct Planted: Equatable, Sendable {
        public let id: UUID
        public let at: Date
    }

    /// How long the entry cue lasts.
    public static let entryCue: TimeInterval = 1.2

    /// Whether a bud still carries its entry cue.
    public func isFresh(_ id: UUID, now: Date = Date()) -> Bool {
        guard let lastPlanted, lastPlanted.id == id else { return false }
        return now.timeIntervalSince(lastPlanted.at) < Self.entryCue
    }
    /// The undo toast; every undoable change goes through it.
    public let toasts = ToastCenter()
    /// The devices paired with this vault, for Settings.
    public let devices: DeviceStore

    private let vault: Vault
    /// The last vault write queued; the next one waits for it, so writes land in order.
    private var pending: Task<Void, Never>?
    /// Writes queued and not yet done; the tree reloads only when none is.
    private var inFlight = 0
    /// Counts local changes, so a snapshot taken before one is never applied after it.
    private var generation = 0
    private var watch: VaultWatch?
    /// Where the vault keeps each bud. Writes look a path up when they run, after the writes
    /// before them, so a bud planted a moment ago is found where the vault put it.
    private var book = PathBook()

    /// A store over a vault. It shows `tree` at once and loads the vault's snapshot over it; the
    /// vault's `watch` reloads it again whenever the vault changes under it.
    public init(vault: Vault, tree: Tree = Tree(), devices: DeviceStore? = nil) {
        self.vault = vault
        self.devices = devices ?? .shared
        let tree = Self.normalized(tree)
        self.tree = tree
        self.center = rootID
        self.layout = LayoutEngine.layout(of: tree, center: rootID)
        self.devices.onSyncFinished = { [weak self] summary in
            guard let message = DevicesText.arrival(summary) else { return }
            self?.toasts.show(Undoable(message: message, systemImage: "arrow.down.to.line"))
        }
        self.devices.onRotationFinished = { [weak self] result in
            self?.toasts.show(Undoable(message: DevicesText.rotated(result), systemImage: "key"))
        }
        Task { @MainActor [weak self] in
            await self?.reload()
            await self?.startWatching()
        }
    }

    /// The store the apps use for now: a memory vault that reads and writes the JSON file, and
    /// starts from the seed world when there is none.
    public convenience init(fileURL: URL? = BudStore.defaultFile, devices: DeviceStore? = nil) {
        var loaded: Tree? = nil
        if let url = fileURL, let data = try? Data(contentsOf: url) {
            loaded = try? JSONDecoder().decode(Tree.self, from: data)
        }
        let tree = loaded ?? Tree.seed()
        self.init(vault: MemoryVault(tree: tree, fileURL: fileURL), tree: tree, devices: devices)
    }

    /// The tree as a vault would hand it back, so a first picture and a reload agree.
    private static func normalized(_ tree: Tree) -> Tree {
        let seen = Dictionary(tree.trashed.map { ($0.id, $0.at) }, uniquingKeysWith: { first, _ in first })
        return Tree(records: tree.records(), trashedAt: { seen[$0] })
    }

    /// Loads the vault's snapshot into the tree. The center stays where it is while its bud
    /// exists; a snapshot that went stale while it was being taken is dropped.
    public func reload() async {
        let started = generation
        guard let records = try? await vault.snapshot(), started == generation, inFlight == 0 else { return }
        let seen = Dictionary(tree.trashed.map { ($0.id, $0.at) }, uniquingKeysWith: { first, _ in first })
        book.keep(records)
        let loaded = Tree(records: records, trashedAt: { seen[$0] }, id: book.id(for:))
        guard loaded != tree else { return }
        tree = loaded
        if center != rootID, tree.bud(center) == nil { center = rootID }
        relayout()
        relight()
    }

    /// Waits until every queued vault write is done and the tree has reloaded after it.
    public func settle() async {
        await pending?.value
    }

    private func startWatching() async {
        watch = try? await vault.watch { [weak self] in
            Task { @MainActor in await self?.reload() }
        }
    }

    /// Runs a vault write after the ones before it, then reloads. A write the vault refuses is
    /// undone by that reload, which shows what the vault holds.
    private func write(_ operation: @escaping @MainActor (Vault) async throws -> Void) {
        inFlight += 1
        let previous = pending
        pending = Task { @MainActor [self] in
            await previous?.value
            try? await operation(vault)
            inFlight -= 1
            await reload()
        }
    }

    /// The path a bud has in the vault right now.
    private func path(_ id: UUID) -> String { book.path(of: id) }

    /// The path a vault knows a parent by: Everything is the top level, nil.
    private func parentPath(_ id: UUID) -> String? {
        if id == rootID { return nil }
        return id == inboxID ? vault.inboxPath : path(id)
    }

    /// Runs a write that gives a bud a new path, and follows it there.
    private func relocate(_ id: UUID, _ operation: (Vault, String) async throws -> String) async throws {
        let old = path(id)
        let new = try await operation(vault, old)
        book.move(from: old, to: new)
    }

    nonisolated public static var defaultFile: URL? {
        // tvOS offers no persistent app folder, only Caches, which the system may reclaim.
        #if os(tvOS)
        let home = FileManager.SearchPathDirectory.cachesDirectory
        #else
        let home = FileManager.SearchPathDirectory.applicationSupportDirectory
        #endif
        guard let base = FileManager.default.urls(for: home, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Bud", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("buds.json")
    }

    public var centerTrail: [UUID] { Array(tree.ancestors(of: center).reversed()) + [center] }

    /// Posted by a Settings window that has no store of its own (the Mac's ⌘,); `userInfo["sample"]`
    /// says whether to start from the sample world. The root view performs it on its store.
    public static let freshStartRequested = Notification.Name("BudStore.freshStartRequested")

    /// Erases every bud on this device, the Trash included, and starts over: empty, or with the
    /// sample world. Not undoable: the dialog asks first. Other devices keep what they hold.
    public func freshStart(sample: Bool) {
        let fresh = Self.normalized(sample ? Tree.seed() : Tree())
        modal = nil
        lens = nil
        place = nil
        center = rootID
        commit { $0 = fresh }
        write { try await $0.reset(to: fresh.records()) }
        toasts.show(Undoable(message: sample ? "Started over with the sample vault" : "Started over", systemImage: "sparkles"))
    }

    /// The open to-do to do next inside the current bud, or, when it has none, the next one
    /// anywhere, marked as elsewhere. Nil when nothing is open at all.
    public var nextStep: (bud: Bud, elsewhere: Bool)? {
        if let here = tree.nextStep(under: center) { return (here, false) }
        if let anywhere = tree.nextStep(under: rootID) { return (anywhere, true) }
        return nil
    }

    /// Plants a bud under a parent and offers to take it back. A blank line plants nothing.
    @discardableResult
    public func add(_ text: String, todo: Bool, under parent: UUID) -> Bud? {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        var planted: Bud?
        commit { planted = $0.add(line, todo: todo, under: parent) }
        guard let planted else { return nil }
        let id = planted.id
        write { [self] vault in
            let path = try await vault.create(
                parent: parentPath(parent), title: line, kind: todo ? .todo : .note, source: nil, preferredPath: id.uuidString
            )
            book.learn(id, at: path)
        }
        lastPlanted = Planted(id: id, at: Date())
        toasts.show(Undoable(message: "Planted under \(tree.title(of: parent))") { [weak self] in
            Task { @MainActor in self?.remove(id) }
        })
        return planted
    }

    /// One line to where it belongs: the Inbox from the capture button (a capture, a note, with its
    /// source), or under the bud on screen, Everything included (a bud of the kind asked for).
    @discardableResult
    public func plant(_ text: String, todo: Bool, at target: PlantTarget, source: String = BudStore.platformSource) -> Bud? {
        switch target {
        case .inbox: return capture(text, source: source)
        case .under(let parent): return add(text, todo: todo, under: parent)
        }
    }

    /// The word a capture carries for the device it was made on.
    nonisolated public static var platformSource: String {
        #if os(macOS)
        return "mac"
        #elseif os(tvOS)
        return "tv"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #endif
    }

    /// Captures one line into the Inbox and offers to take it back. A blank line captures nothing.
    @discardableResult
    public func capture(_ text: String, source: String = BudStore.platformSource) -> Bud? {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        var captured: Bud?
        commit { captured = $0.capture(line, source: source) }
        guard let captured else { return nil }
        let id = captured.id
        write { [self] vault in
            let path = try await vault.create(
                parent: vault.inboxPath, title: line, kind: .note, source: source, preferredPath: id.uuidString
            )
            book.learn(id, at: path)
        }
        lastPlanted = Planted(id: id, at: Date())
        toasts.show(Undoable(message: "Captured to the Inbox") { [weak self] in
            Task { @MainActor in self?.remove(id) }
        })
        return captured
    }

    /// A line from the ⌥Space panel: captured with its device word, the app it came from in the
    /// body, made a to-do when asked.
    @discardableResult
    public func capture(_ line: CaptureRelay.Line) -> Bud? {
        guard let bud = capture(line.text, source: line.source) else { return nil }
        if !line.body.isEmpty { setBody(bud.id, line.body) }
        if line.todo { makeTodo(bud.id) }
        return tree.bud(bud.id)
    }

    /// Gives a bud and its branch a new parent and offers to move it back. A move the tree
    /// refuses (under itself or its own descendant) does nothing and says nothing.
    @discardableResult
    public func move(_ id: UUID, under parent: UUID) -> Bool {
        guard let from = tree.bud(id)?.parent else { return false }
        guard put(id, under: parent) else { return false }
        toasts.show(Undoable(message: "Moved to \(tree.title(of: parent))") { [weak self] in
            Task { @MainActor in self?.put(id, under: from) }
        })
        return true
    }

    /// The move itself, without a toast.
    @discardableResult
    private func put(_ id: UUID, under parent: UUID) -> Bool {
        var moved = false
        commit { moved = $0.move(id, under: parent) }
        guard moved else { return false }
        write { [self] _ in
            let up = parentPath(parent)
            try await relocate(id) { try await $0.move($1, to: up) }
        }
        return true
    }

    public func update(_ id: UUID, text: String, todo: Bool) {
        guard let before = tree.bud(id) else { return }
        commit { $0.update(id, text: text, todo: todo) }
        write { [self] vault in
            if text != before.text { try await relocate(id) { try await $0.rename($1, to: text) } }
            if todo, before.state == nil { try await vault.setState(path(id), .open) }
            if !todo, before.state != nil { try await vault.setState(path(id), nil) }
        }
    }

    /// Sets the state of each bud, here and in the vault.
    private func set(_ state: BudState, on ids: [UUID]) {
        commit { tree in
            for id in ids {
                guard let i = tree.buds.firstIndex(where: { $0.id == id }), tree.buds[i].state != nil else { continue }
                tree.buds[i].state = state
            }
        }
        write { [self] vault in
            for id in ids { try await vault.setState(path(id), state) }
        }
    }

    /// What every checkbox calls. A done to-do reopens at once; an open to-do with nothing open
    /// inside closes at once; one with open to-dos inside asks first, through the Close branch
    /// dialog, since closing never cascades on its own.
    public func tick(_ id: UUID) {
        guard let bud = tree.bud(id), bud.isTodo else { return }
        if bud.isDone {
            set(.open, on: [id])
        } else if tree.openCount(under: id) > 0 {
            modal = .closeBranch(id: id)
        } else {
            close(id, cascade: false)
        }
    }

    /// Closes a to-do, and with `cascade` every open to-do under it, and offers to take it back:
    /// Undo reopens exactly the ones that changed.
    public func close(_ id: UUID, cascade: Bool) {
        let title = tree.title(of: id)
        var changed: [UUID] = []
        var closed = tree
        changed = closed.close(id, cascade: cascade)
        guard !changed.isEmpty else { return }
        set(.done, on: changed)
        let inside = changed.count - 1
        let message = inside == 0 ? "Closed \(title)" : "Closed \(title) and \(inside) inside"
        toasts.show(Undoable(message: message) { [weak self] in
            Task { @MainActor in self?.set(.open, on: changed) }
        })
    }

    public func toggle(_ id: UUID) {
        guard let state = tree.bud(id)?.state else { return }
        set(state == .done ? .open : .done, on: [id])
    }

    public func setBody(_ id: UUID, _ body: String) {
        commit { $0.setBody(id, body) }
        write { [self] in try await $0.setBody(path(id), body) }
    }

    public func setWhen(_ id: UUID, _ when: Date?) {
        commit { $0.setWhen(id, when) }
        write { [self] in try await $0.setWhen(path(id), when) }
    }

    public func setDue(_ id: UUID, _ due: Date?) {
        commit { $0.setDue(id, due) }
        write { [self] in try await $0.setDue(path(id), due) }
    }

    public func setPinned(_ id: UUID, _ pinned: Bool) {
        commit { $0.setPinned(id, pinned) }
        write { [self] in try await $0.setPinned(path(id), pinned) }
    }

    /// Trades the places of two siblings in the orbit and offers to trade them back.
    @discardableResult
    public func swap(_ a: UUID, _ b: UUID, message: String = "Swapped") -> Bool {
        guard trade(a, b) else { return false }
        toasts.show(Undoable(message: message) { [weak self] in
            Task { @MainActor in _ = self?.trade(a, b) }
        })
        return true
    }

    /// Trades places with the sibling before (-1) or after (1): the reorder that needs no drag.
    @discardableResult
    public func shift(_ id: UUID, by offset: Int) -> Bool {
        guard let other = tree.sibling(of: id, offset: offset) else { return false }
        return swap(id, other, message: offset < 0 ? "Moved earlier" : "Moved later")
    }

    private func trade(_ a: UUID, _ b: UUID) -> Bool {
        var traded = false
        commit { traded = $0.swap(a, b) }
        guard traded, let parent = tree.bud(a)?.parent else { return false }
        let order = tree.children(of: parent).map(\.id)
        write { [self] in try await $0.reorder(order.map(path), under: parentPath(parent)) }
        return true
    }

    /// Takes a bud and its branch away without a trace: no Trash, no toast.
    public func remove(_ id: UUID) {
        commit { $0.remove(id) }
        write { [self] vault in
            try await relocate(id) { try await $0.trash($1) }
            try await vault.deleteForever(path(id))
        }
    }

    /// Trashes a bud and its branch and offers to take it back; Undo restores the branch as it was.
    public func trash(_ id: UUID) {
        guard tree.bud(id) != nil else { return }
        let title = tree.title(of: id)
        sendToTrash(id)
        toasts.show(Undoable(message: "Trashed \(title)") { [weak self] in
            Task { @MainActor in self?.putBack(id) }
        })
    }

    private func sendToTrash(_ id: UUID) {
        commit { $0.trash(id) }
        write { [self] _ in try await relocate(id) { try await $0.trash($1) } }
    }

    private func putBack(_ id: UUID) {
        commit { $0.restore(id) }
        write { [self] _ in try await relocate(id) { try await $0.restore($1) } }
    }

    /// Puts a branch back from the Trash and offers to trash it again.
    public func restore(_ id: UUID) {
        guard let branch = tree.trashed.first(where: { $0.id == id }) else { return }
        putBack(id)
        toasts.show(Undoable(message: "Restored \(branch.head.text)") { [weak self] in
            Task { @MainActor in self?.sendToTrash(id) }
        })
    }

    /// Drops a branch from the Trash for good. Not undoable: the dialog asks first.
    public func deleteForever(_ id: UUID) {
        commit { $0.deleteForever(id) }
        write { [self] in try await $0.deleteForever(path(id)) }
    }

    public func emptyTrash() {
        commit { $0.emptyTrash() }
        write { try await $0.emptyTrash() }
    }

    /// Makes a note a to-do, open. A to-do stays what it is.
    public func makeTodo(_ id: UUID) {
        guard let bud = tree.bud(id), !bud.isTodo else { return }
        update(id, text: bud.text, todo: true)
    }

    /// Open as file: the Files view with this bud as the page. The center is the selection there.
    public func openAsFile(_ id: UUID) {
        center = id
        lens = nil
        place = nil
        surface = .files
    }

    /// The Files view on a lens.
    public func open(_ lens: Lens) {
        self.lens = lens
        surface = .files
    }

    /// The Files view on a place.
    public func open(_ place: Place) {
        lens = nil
        self.place = place
        surface = .files
    }

    /// Go anywhere to a bud: an inbox bud opens the Inbox page, since it has no place on the
    /// canvas and no file of its own; any other bud is centered, or opened as a file in Files.
    public func go(to id: UUID, inFiles: Bool) {
        if tree.ancestors(of: id).contains(inboxID) {
            openInbox()
        } else if inFiles {
            openAsFile(id)
        } else {
            center = id
            surface = .canvas
        }
    }

    /// The Files view on the Inbox.
    public func openInbox() { open(.inbox) }
    public func openArchive() { open(.archive) }
    public func openTrash() { open(.trash) }

    public func back() {
        guard center != rootID else { return }
        center = tree.parent(of: center) ?? rootID
    }

    private func commit(_ change: (inout Tree) -> Void) {
        generation += 1
        change(&tree)
        if center != rootID, tree.bud(center) == nil { center = rootID }
        relayout()
        relight()
    }

    private func relayout() {
        layout = LayoutEngine.layout(of: tree, center: center)
    }

    /// Asks the lens again without a change: the day it reads Today and Overdue against moved.
    public func refreshLens() {
        relight()
    }

    /// The lens reads the tree alone, so a new center leaves it as it is.
    private func relight() {
        canvasLight = canvasLens?.light(tree) ?? [:]
    }
}
#endif
