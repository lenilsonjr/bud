#if canImport(SwiftUI)
import Foundation
import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A query across every thread, shown as a page in Files.
public enum Lens: String, CaseIterable, Sendable {
    case today = "Today", todos = "To-dos", pinned = "Pinned"
}

/// A place that holds buds and has a page of its own in Files, beside Everything's tree: the
/// Inbox (captures), the Archive (finished chapters), the Trash (recoverable branches), and the
/// Library's Warehouse (templates) and Triggers (what stamps them).
public enum Place: String, CaseIterable, Sendable {
    case inbox = "Inbox", archive = "Archive", trash = "Trash", warehouse = "Warehouse", triggers = "Triggers"
}

/// The tree, the current center of the web, and the layout derived from both.
/// Every mutation goes to the vault and reloads from it; the layout is recomputed once per change, not per frame.
@MainActor
public final class BudStore: ObservableObject {
    @Published public private(set) var tree: Tree {
        didSet {
            links = LinkGraph(tree)
            backlinkCache = [:]
            dropGoneFacets()
            calendarState.keep(threads: Set(tree.children(of: rootID).map(\.id)))
            regroup()
        }
    }
    /// Which buds link to which, read again whenever the tree changes.
    @Published public private(set) var links = LinkGraph()
    /// The rows of Linked from, kept from the first ask until the tree changes, so a page does
    /// not read every body again on each publish.
    private var backlinkCache: [UUID: [Backlink]] = [:]
    @Published public private(set) var layout: Layout
    @Published public var center: UUID {
        didSet {
            if center != oldValue {
                relayout()
                lens = nil
                place = nil
                savedLens = nil
            }
        }
    }
    /// The place Files shows instead of the center's page; a change of center or lens clears it.
    @Published public var place: Place? = nil {
        didSet { if place != nil { savedLens = nil } }
    }
    /// Whether Files shows the Inbox.
    public var inboxOpen: Bool {
        get { place == .inbox }
        set { place = newValue ? .inbox : nil }
    }
    @Published public var surface: Surface = .canvas
    /// Whether Go anywhere is open over the window.
    @Published public var searching = false
    /// The lens Files shows instead of the center's page; a change of center clears it.
    @Published public var lens: Lens? = nil {
        didSet {
            if lens != nil {
                place = nil
                savedLens = nil
            }
        }
    }
    /// The saved lens Files shows instead of the center's page, by its id; a change of center,
    /// lens or place clears it.
    @Published public var savedLens: UUID? = nil {
        didSet {
            if savedLens != nil {
                lens = nil
                place = nil
            }
            if savedLens != oldValue { regroup() }
        }
    }
    /// What the open saved lens finds, by thread, worked out once per change of tree, lens or
    /// day, not on every publish.
    @Published public private(set) var savedLensThreads: [LensThread] = []
    /// The lenses the person named and kept, sorted by name, as the vault holds them.
    @Published public private(set) var savedLenses: [SavedLens] = [] {
        didSet {
            if savedLenses != oldValue {
                syncSavedFacets()
                // The open lens changed: its page again. One that went closes the page, which
                // works it out then.
                if let open = savedLens, let now = saved(open), now != oldValue.first(where: { $0.id == open }) { regroup() }
            }
        }
    }
    /// The rows ticked in the canvas lens menu, in the order they were ticked; they set
    /// `canvasLens` to the question they ask together.
    @Published public var canvasFacets: [LensFacet] = [] {
        didSet { if canvasFacets != oldValue { canvasLens = LensFacet.query(of: canvasFacets) } }
    }
    /// The question the canvas is asked: its hits stay lit and the rest fades. Nil for none.
    @Published public internal(set) var canvasLens: LensQuery? = nil {
        didSet { if canvasLens != oldValue { relight() } }
    }
    /// How each bud stands under the canvas lens, worked out once per change of tree or lens.
    @Published public private(set) var canvasLight: [UUID: LensQuery.Match] = [:]
    /// The canvas scale: 1 is 100%. Pinch changes it; the zoom control in the bar resets it.
    @Published public var zoom: CGFloat = 1
    /// Whether Files shows each sidebar; iOS follows the window shape until a toggle decides.
    @Published public var sidebar = SidebarVisibility(followsWindow: BudStore.sidebarFollowsWindow)
    /// The panels around the page: where each sits and which are folded. The layout is read from
    /// the vault and changed through `arrange`; folding is this device's alone.
    @Published public var panels = PanelState()
    /// The chat in the Agent panel. Empty until something is said; no agent answers yet.
    @Published public var agent = AgentConversation()
    /// Which tag columns each bud's board shows, by the bud's id, as the vault holds them. A bud
    /// with no entry shows the tags in use inside it.
    @Published public var boards: [UUID: BoardColumns] = [:]
    /// The cards' pictures, decoded once each and kept by the bud's id; a bud not here has not
    /// been asked for. Nothing is published for a load that changes nothing.
    @Published public private(set) var pictures: [UUID: BoardPictureState] = [:]
    /// Which app runs the agent and with which model. Kept in this device's defaults only:
    /// another Mac has its own installs.
    @Published public var agentChoice: AgentChoice {
        didSet { if agentChoice != oldValue { agentChoice.write(to: defaults) } }
    }
    /// What is installed on this Mac, read from the known install places, PATH and the home
    /// directory when the picker opens.
    public let agentApps: AgentApps
    /// Where this device's own choices are kept.
    private let defaults: UserDefaults

    /// What every tour's launch argument starts with. An app launched with one is drawing
    /// pictures: it opens its vault but starts no sync node, fires no trigger, brings in no old
    /// file and listens for no capture.
    public static let tourPrefix = "-bud-"
    /// The launch argument for an app that hosts pictures and shows nothing of its own, as the
    /// iOS catalog's host app does.
    public static let picturesArgument = tourPrefix + "pictures"

    /// Whether these launch arguments are a tour's, the pictures argument among them.
    public static func launchedForPictures(_ arguments: [String]) -> Bool {
        arguments.contains { $0.hasPrefix(tourPrefix) }
    }

    static var sidebarFollowsWindow: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }
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

    /// The moment it is: the device store's clock, the real one in the app and a fixed moment in
    /// a still picture, so Today, the day labels and the counts come out the same every run. The
    /// views read it here rather than the wall clock.
    public var now: Date { devices.now() }

    /// Whether a bud still carries its entry cue.
    public func isFresh(_ id: UUID, now: Date? = nil) -> Bool {
        guard let lastPlanted, lastPlanted.id == id else { return false }
        return (now ?? self.now).timeIntervalSince(lastPlanted.at) < Self.entryCue
    }
    /// The accounts this device reads below the soil. Nothing in them reaches the vault until an
    /// item is planted.
    @Published public var sources: [SourceAccount] = []
    /// Whether the soil is folded into its strip. Kept on this device only.
    @Published public var soilFolded = UserDefaults.standard.bool(forKey: BudStore.soilFoldedKey) {
        didSet { UserDefaults.standard.set(soilFolded, forKey: Self.soilFoldedKey) }
    }
    static let soilFoldedKey = "soilFolded"
    /// The calendar the days are counted in, beside `now` on the device store: the system's, or
    /// the one a picture fixes.
    public var calendar: Calendar { devices.calendar }
    /// The Calendar view's range, layout, hidden threads and Show switches. Kept on this device only.
    @Published public var calendarState = CalendarState.load(from: .standard) {
        didSet { if calendarState != oldValue { calendarState.save(to: .standard) } }
    }
    /// The day the calendar is looking at; nil for today.
    @Published public var calendarDate: Date? = nil
    /// How each planted bud stands with its source, by its `from` key, as the device that keeps
    /// it live last saw it.
    @Published public var marks: [String: SourceMark] = [:]

    /// A recorded key changes what every view binds and what the menu bar lists, and they all
    /// read the store, so the layout's changes go out as the store's.
    private var keyFeed: AnyCancellable?
    private var soilFeed: AnyCancellable?

    private var liveFeed: AnyCancellable?
    /// The Library's triggers, as the vault has them.
    @Published public internal(set) var triggers: [Trigger] = []
    var firing: Task<Void, Never>?
    private weak var soil: SourceStore?
    private var keepingLive = false

    /// Shows what a source store reads below the soil, starts it reading, and keeps the buds
    /// planted from it live after each read.
    public func follow(_ soil: SourceStore) {
        self.soil = soil
        soil.deviceName = Self.deviceName
        let vault = vault
        Task { await soil.use(vault) }
        soilFeed = soil.$accounts.receive(on: RunLoop.main).sink { [weak self] in self?.sources = $0 }
        liveFeed = soil.$refreshed.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            Task { @MainActor in await self?.keepLive(soil) }
        }
        soil.start()
    }

    /// How a planted bud stands with its source: its `from-state`, with the last sync this device
    /// made. Nil for a bud that was not planted.
    public func mark(of bud: Bud) -> SourceMark? {
        guard let from = bud.from else { return nil }
        var mark = marks[from] ?? SourceMark()
        if let state = SourceMark(fromState: bud.fromState) {
            mark.status = state.status
            mark.at = state.at
        }
        return mark
    }

    /// What each planted item showed at its source the last time this device looked, by `from` key.
    private var lastSeen: [String: SourceSnapshot] = {
        guard let data = UserDefaults.standard.data(forKey: BudStore.lastSeenKey) else { return [:] }
        return (try? JSONDecoder().decode([String: SourceSnapshot].self, from: data)) ?? [:]
    }() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(lastSeen), forKey: Self.lastSeenKey) }
    }
    static let lastSeenKey = "sourceSnapshots"

    /// Brings every planted bud in line with what its source shows now: the fields the source owns
    /// change only when they changed there, and `from-state` says moved, cancelled or gone.
    public func keepLive(_ soil: SourceStore, now: Date? = nil) async {
        guard !keepingLive else { return }
        let now = now ?? self.now
        keepingLive = true
        defer { keepingLive = false }
        let kinds = await soil.holdLeases()
        let all = tree.buds.filter { $0.from != nil }
        // Every device shows the last sync, whichever device ran it.
        for bud in all {
            guard let from = bud.from, let kind = SourceRowText.origin(from).kind, let lease = soil.lastSync(of: kind) else { continue }
            var mark = marks[from] ?? SourceMark()
            mark.synced = lease.synced
            mark.device = lease.name
            marks[from] = mark
        }
        let planted = all.filter { $0.from.flatMap { SourceRowText.origin($0).kind }.map(kinds.contains) ?? false }
        guard !planted.isEmpty else { return }
        let sightings = await soil.sightings(for: planted.map { ($0.from!, $0.when) })
        for bud in planted {
            guard let from = bud.from, let sighting = sightings[from], let kind = SourceRowText.origin(from).kind,
                  let current = tree.bud(bud.id) else { continue }
            let result = LiveRules.changes(for: current, kind: kind, sighting: sighting, last: lastSeen[from], now: now)
            apply(result.changes, to: current)
            if let seen = result.seen, !(lastSeen[from]?.same(as: seen) ?? false) { lastSeen[from] = seen }
            if case .seen(let item) = sighting, let url = item.url { marks[from, default: SourceMark()].url = url }
        }
    }

    private func apply(_ changes: [LiveChange], to bud: Bud) {
        for change in changes {
            switch change {
            case .rename(let title): update(bud.id, text: title, todo: bud.isTodo)
            case .when(let when): setWhen(bud.id, when)
            case .due(let due): setDue(bud.id, due)
            case .body(let body): setBody(bud.id, body)
            case .state(.open):
                if !bud.isTodo { update(bud.id, text: tree.bud(bud.id)?.text ?? bud.text, todo: true) }
                else if bud.isDone { set(.open, on: [bud.id]) }
            case .state:
                if bud.isTodo, !bud.isDone { set(.done, on: [bud.id]) }
            case .mark(let state): setFromState(bud.id, state)
            }
        }
    }

    /// Sets a planted bud's `from-state`, here and in the vault.
    public func setFromState(_ id: UUID, _ state: String?) {
        commit { tree in
            guard let i = tree.buds.firstIndex(where: { $0.id == id }) else { return }
            tree.buds[i].fromState = state
        }
        write { [self] _ in try await edit(id) { try await $0.setFromState($1, state) } }
    }

    /// One root per account, in the order the accounts were connected.
    public func roots(now: Date? = nil) -> [Root] {
        sources.map { Root($0, now: now ?? self.now) }
    }

    /// The undo toast; every undoable change goes through it.
    public let toasts = ToastCenter()
    /// The devices paired with this vault, for Settings.
    public let devices: DeviceStore
    /// The keys this store's window answers to: the app's layout, or one of a test's own, so a
    /// picture of the sheet shows the table's defaults whatever the process's defaults hold.
    public let keys: KeyLayout

    private let vault: Vault
    /// The last vault write queued; the next one waits for it, so writes land in order.
    private var pending: Task<Void, Never>?
    /// Writes queued and not yet done; the tree reloads only when none is.
    private var inFlight = 0
    /// Counts local changes, so a snapshot taken before one is never applied after it.
    private var generation = 0
    /// Counts saved lenses kept or let go here, so a read of the vault taken before one is
    /// never applied after it.
    private var lensEdits = 0
    /// The same for the boards' columns and for the panels' layout.
    private var boardEdits = 0
    private var layoutEdits = 0
    /// Saved lenses deleted here whose Undo may still bring them back, the latest last and only
    /// a few, kept up to date with tag renames made since.
    private var deletedLenses: [SavedLens] = []
    static let deletedLensesKept = 5
    private var watch: VaultWatch?
    /// Where the vault keeps each bud. Writes look a path up when they run, after the writes
    /// before them, so a bud planted a moment ago is found where the vault put it.
    private var book = PathBook()

    /// A store over a vault. It shows `tree` at once and loads the vault's snapshot over it; the
    /// vault's `watch` reloads it again whenever the vault changes under it. `defaults` is where
    /// this device's own choices go; `agentApps` is what the agent picker finds installed;
    /// `keys` is the layout the window and its sheet read, the app's unless a test brings one.
    public init(vault: Vault, tree: Tree = Tree(), devices: DeviceStore? = nil, defaults: UserDefaults = .standard, agentApps: AgentApps = AgentApps(), keys: KeyLayout = Keys.layout) {
        self.vault = vault
        self.devices = devices ?? .shared
        self.keys = keys
        self.defaults = defaults
        self.agentApps = agentApps
        self.agentChoice = AgentChoice.read(from: defaults, in: agentApps)
        let tree = Self.normalized(tree)
        self.tree = tree
        self.links = LinkGraph(tree)
        self.center = rootID
        self.layout = LayoutEngine.layout(of: tree, center: rootID)
        keyFeed = keys.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        self.devices.onSyncFinished = { [weak self] summary in
            // A sync writes the files itself, which the vault's watch does not report.
            Task { @MainActor in
                await self?.reload()
                await self?.soil?.reloadShared()
                await self?.reloadTriggers()
                await self?.reloadLayout()
                await self?.reloadBoards()
                await self?.reloadLenses()
            }
            guard let message = DevicesText.arrival(summary) else { return }
            self?.toasts.show(Undoable(message: message, systemImage: "arrow.down.to.line"))
        }
        self.devices.onRotationFinished = { [weak self] result in
            self?.toasts.show(Undoable(message: DevicesText.rotated(result), systemImage: "key"))
        }
        Task { @MainActor [weak self] in
            await self?.reload()
            await self?.reloadTriggers()
            await self?.reloadLayout()
            await self?.reloadBoards()
            await self?.reloadLenses()
            await self?.startWatching()
        }
    }

    /// The store the apps use for now: a memory vault that reads and writes the JSON file, and
    /// starts from the seed world when there is none, told from the device store's clock, so a
    /// picture on a fixed clock shows the same today on every run.
    public convenience init(fileURL: URL? = BudStore.defaultFile, devices: DeviceStore? = nil, keys: KeyLayout = Keys.layout) {
        var loaded: Tree? = nil
        if let url = fileURL, let data = try? Data(contentsOf: url) {
            loaded = try? JSONDecoder().decode(Tree.self, from: data)
        }
        let tree = loaded ?? Tree.seed(now: (devices ?? .shared).now())
        self.init(vault: MemoryVault(tree: tree, fileURL: fileURL), tree: tree, devices: devices, keys: keys)
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
        guard let snapshot = try? await vault.snapshot(), started == generation, inFlight == 0 else { return }
        let records = BudRecord.withoutTrashFolders(snapshot)
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
    /// A write that queues another while it runs is waited for along with the one it queued.
    public func settle() async {
        while let last = pending {
            await last.value
            if pending == last { return }
        }
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

    /// Runs a write to a map beside the buds after the writes before it. The tree is not
    /// touched, so nothing reloads; `failed` runs in the queue, when the vault refuses it, so
    /// what it queues lands before `settle` returns.
    private func writeBeside(_ operation: @escaping @MainActor (Vault) async throws -> Void, failed: @escaping @MainActor () -> Void) {
        let previous = pending
        pending = Task { @MainActor [self] in
            await previous?.value
            do {
                try await operation(vault)
            } catch {
                failed()
            }
        }
    }

    /// Reads a map beside the buds once the writes queued here have landed and hands it to
    /// `apply`. A read that a change made here overtook, `edits` having moved while it was
    /// read, is read again once that change has landed.
    private func reread(_ map: SharedMap, edits: KeyPath<BudStore, Int>, apply: ([String: String]) -> Void) async {
        while true {
            await settle()
            guard let read = await readBeside(map, edits: edits) else { return }
            if !read.overtaken {
                apply(read.stored)
                return
            }
        }
    }

    /// The same read, queued behind the writes: after a write the vault refused, so the store
    /// is back in step before `settle` returns.
    private func queueReread(_ map: SharedMap, edits: KeyPath<BudStore, Int>, apply: @escaping @MainActor ([String: String]) -> Void) {
        let previous = pending
        pending = Task { @MainActor [self] in
            await previous?.value
            guard let read = await readBeside(map, edits: edits) else { return }
            if read.overtaken {
                queueReread(map, edits: edits, apply: apply)
            } else {
                apply(read.stored)
            }
        }
    }

    /// One read of a map beside the buds, and whether a change made here overtook it while it
    /// was read; nil when the vault could not be read.
    private func readBeside(_ map: SharedMap, edits: KeyPath<BudStore, Int>) async -> (stored: [String: String], overtaken: Bool)? {
        let started = self[keyPath: edits]
        guard let stored = try? await vault.shared(map) else { return nil }
        return (stored, started != self[keyPath: edits])
    }

    /// The path a bud has in the vault right now.
    private func path(_ id: UUID) -> String { book.path(of: id) }

    /// The path a vault knows a parent by: Everything is the top level, nil.
    private func parentPath(_ id: UUID) -> String? {
        if id == rootID { return nil }
        if id == inboxID { return vault.inboxPath }
        return id == warehouseID ? vault.warehousePath : path(id)
    }

    /// Runs a write to a bud's body or properties, and follows the bud to the file the vault may
    /// have given it.
    private func edit(_ id: UUID, _ operation: (Vault, String) async throws -> Void) async throws {
        let old = path(id)
        try await operation(vault, old)
        book.move(from: old, to: vault.pathAfterEdit(old))
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

    /// The buds whose body links to a page, read once per change of the tree.
    public func backlinks(to id: UUID) -> [Backlink] {
        if let known = backlinkCache[id] { return known }
        let found = tree.backlinks(to: id)
        backlinkCache[id] = found
        return found
    }

    /// The bud's file as the vault holds it, once the writes before have landed. Nil for a bud
    /// the vault does not know.
    public func fileText(of id: UUID) async -> String? {
        await pending?.value
        return try? await vault.text(path(id))
    }

    /// Posted by a Settings window that has no store of its own (the Mac's ⌘,); `userInfo["sample"]`
    /// says whether to start from the sample world. The root view performs it on its store.
    public static let freshStartRequested = Notification.Name("BudStore.freshStartRequested")

    /// Erases every bud on this device, the Trash included, and starts over: empty, or with the
    /// sample world. Not undoable: the dialog asks first. Other devices keep what they hold.
    public func freshStart(sample: Bool) {
        let fresh = Self.normalized(sample ? Tree.seed(now: now) : Tree())
        modal = nil
        lens = nil
        place = nil
        savedLens = nil
        center = rootID
        commit { $0 = fresh }
        write { [self] vault in
            let planted = try await vault.reset(to: fresh.records())
            book = PathBook()
            for (record, path) in planted { book.learn(Bud.id(forPath: record), at: path) }
        }
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
        commit { planted = $0.add(line, todo: todo, under: parent, created: now) }
        guard let planted else { return nil }
        let id = planted.id
        write { [self] vault in
            let path = try await vault.create(
                parent: parentPath(parent), title: line, kind: todo ? .todo : .note, source: nil, preferredPath: id.uuidString
            )
            book.learn(id, at: path)
        }
        lastPlanted = Planted(id: id, at: now)
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

    /// Plants a source item where it was dropped, as a bud carrying its `from` key, and offers to
    /// take it back. An item planted before is not planted twice: the canvas goes to its bud.
    @discardableResult
    public func plant(_ item: SourceItem, from account: SourceAccount, at target: PlantTarget) -> Bud {
        let key = account.kind.key(item.id)
        if let bud = tree.planted(from: key) {
            if bud.parent == inboxID { inboxOpen = true } else { center = bud.parent }
            lastPlanted = Planted(id: bud.id, at: now)
            toasts.show(Undoable(message: "Already planted in \(tree.title(of: bud.parent))", systemImage: "leaf"))
            return bud
        }
        let parent: UUID
        switch target {
        case .inbox: parent = inboxID
        case .under(let id): parent = id
        }
        var planted = Bud(text: item.title)
        commit { planted = $0.plant(item.title, todo: item.todo, under: parent, from: key, created: now) }
        let id = planted.id
        write { [self] vault in
            let planting = try await vault.plant(
                parent: parentPath(parent), title: item.title, kind: item.todo ? .todo : .note, from: key,
                preferredPath: id.uuidString
            )
            book.learn(id, at: planting.path)
        }
        // A calendar owns the event's day: the bud starts with it.
        if account.kind == .calendar, let date = item.date { setWhen(id, date) }
        // Linear and GitHub own the body: the team and state, or the repository and kind. Linear
        // owns the issue's due date too.
        if account.kind == .linear || account.kind == .github {
            if account.kind == .linear, let date = item.date { setDue(id, date) }
            if let detail = item.detail { setBody(id, detail) }
        }
        lastSeen[key] = SourceSnapshot(item, kind: account.kind, at: now)
        lastPlanted = Planted(id: id, at: now)
        toasts.show(Undoable(message: "Planted in \(tree.title(of: parent)), from \(account.name)") { [weak self] in
            Task { @MainActor in self?.remove(id) }
        })
        return planted
    }

    /// What a person calls this device: "Mac", "iPad", "iPhone" or "TV".
    nonisolated public static var deviceName: String {
        switch platformSource {
        case "mac": return "Mac"
        case "ipad": return "iPad"
        case "iphone": return "iPhone"
        default: return "TV"
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
        commit { captured = $0.capture(line, source: source, created: now) }
        guard let captured else { return nil }
        let id = captured.id
        write { [self] vault in
            let path = try await vault.create(
                parent: vault.inboxPath, title: line, kind: .note, source: source, preferredPath: id.uuidString
            )
            book.learn(id, at: path)
        }
        lastPlanted = Planted(id: id, at: now)
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

    /// A new title rewrites the links it would break, and offers to take both back. The bodies
    /// are written only once the vault has taken the new title.
    public func update(_ id: UUID, text: String, todo: Bool) {
        guard let before = tree.bud(id) else { return }
        let relinked = text != before.text ? tree.relinked(renaming: id, to: text) : [:]
        let bodies = relinked.keys.reduce(into: [UUID: String]()) { $0[$1] = tree.bud($1)?.body }
        commit { tree in
            tree.update(id, text: text, todo: todo)
            for (other, body) in relinked { tree.setBody(other, body) }
        }
        write { [self] vault in
            if text != before.text { try await relocate(id) { try await $0.rename($1, to: text) } }
            if todo, before.state == nil { try await edit(id) { try await $0.setState($1, .open) } }
            if !todo, before.state != nil { try await edit(id) { try await $0.setState($1, nil) } }
            for (other, body) in relinked { try await edit(other) { try await $0.setBody($1, body) } }
        }
        guard !relinked.isEmpty else { return }
        let count = relinked.count
        toasts.show(Undoable(message: count == 1 ? "Updated links in 1 bud" : "Updated links in \(count) buds", systemImage: "link") {
            [weak self] in
            Task { @MainActor in self?.undoRename(id, from: text, to: before.text, relinked: relinked, bodies: bodies) }
        })
    }

    /// Takes a rename back, and the links it rewrote, where nothing has changed them since.
    private func undoRename(_ id: UUID, from title: String, to old: String, relinked: [UUID: String], bodies: [UUID: String]) {
        guard let now = tree.bud(id), now.text == title else { return }
        let restore = bodies.filter { tree.bud($0.key)?.body == relinked[$0.key] }
        commit { tree in
            tree.update(id, text: old, todo: now.isTodo)
            for (other, body) in restore { tree.setBody(other, body) }
        }
        write { [self] _ in
            try await relocate(id) { try await $0.rename($1, to: old) }
            for (other, body) in restore { try await edit(other) { try await $0.setBody($1, body) } }
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
        write { [self] _ in
            for id in ids { try await edit(id) { try await $0.setState($1, state) } }
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
        write { [self] _ in try await edit(id) { try await $0.setBody($1, body) } }
    }

    public func setWhen(_ id: UUID, _ when: Date?) {
        commit { $0.setWhen(id, when) }
        write { [self] _ in try await edit(id) { try await $0.setWhen($1, when) } }
    }

    public func setDue(_ id: UUID, _ due: Date?) {
        commit { $0.setDue(id, due) }
        write { [self] _ in try await edit(id) { try await $0.setDue($1, due) } }
    }

    public func setPinned(_ id: UUID, _ pinned: Bool) {
        commit { $0.setPinned(id, pinned) }
        write { [self] _ in try await edit(id) { try await $0.setPinned($1, pinned) } }
    }

    // MARK: Tags

    /// Adds a tag to a bud's own list, unless the bud carries it already.
    public func addTag(_ id: UUID, _ tag: String) {
        guard let tag = BudTags.clean(tag), let bud = tree.bud(id),
              !bud.tags.contains(where: { BudTags.key($0) == BudTags.key(tag) }) else { return }
        commit { $0.addTag(id, tag) }
        write { [self] _ in
            do {
                try await edit(id) { try await $0.addTag($1, tag) }
            } catch {
                toasts.show(Undoable(message: "Couldn't add #\(tag) to this bud", systemImage: "exclamationmark.triangle"))
            }
        }
    }

    /// Takes a tag out of a bud's own list and offers to put it back where it was.
    public func removeTag(_ id: UUID, _ tag: String) {
        guard let tags = tree.bud(id)?.tags,
              let index = tags.firstIndex(where: { BudTags.key($0) == BudTags.key(tag) }) else { return }
        let own = tags[index]
        commit { $0.removeTag(id, own) }
        let edits = TagEdits()
        write { [self] _ in try await edit(id) { edits.byID[id] = try await $0.removeTag($1, own) } }
        toasts.show(Undoable(message: "Removed #\(own)", systemImage: "number") { [weak self] in
            Task { @MainActor in self?.undoRemoveTag(id, own, at: index, edits) }
        })
    }

    /// Puts the file back as it was before the remove; where it has changed since, adds the
    /// tag to its list instead.
    private func undoRemoveTag(_ id: UUID, _ tag: String, at index: Int, _ edits: TagEdits) {
        commit { $0.addTag(id, tag, at: index) }
        write { [self] vault in
            if let record = edits.byID[id], (try? await vault.restoreText(path(id), from: record.after, to: record.before)) == true {
                return
            }
            do {
                try await edit(id) { try await $0.addTag($1, tag) }
            } catch {
                toasts.show(Undoable(message: "Couldn't put #\(tag) back on this bud", systemImage: "exclamationmark.triangle"))
            }
        }
    }

    /// Renames or merges a tag in every bud outside the Trash and offers to take it back.
    public func renameTag(_ from: String, to: String) {
        guard let from = BudTags.clean(from), let to = BudTags.clean(to), from != to else { return }
        var changed: [UUID] = []
        commit { changed = $0.renameTag(from, to: to) }
        // Saved lenses sync, so one may ask for a tag no bud here carries.
        let asked = savedLenses.contains { $0.renamingTag(from, to: to) != nil }
        let reachesDeleted = deletedLenses.contains { $0.renamingTag(from, to: to) != nil }
        guard !changed.isEmpty || asked || reachesDeleted else { return }
        let edits = TagEdits()
        let lenses = LensTagRename()
        let reachesBuds = !changed.isEmpty
        let buds = changed.count
        // Once the buds have their new tag, the lenses follow; once the vault has taken the
        // lenses' writes, or said it would not, the rows and the toast say what happened.
        let done: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            self.renameTagInLenses(from, to: to, into: lenses) { plan, refused in
                // Nothing changed at all: the rows and the deleted lenses stay as they are.
                guard reachesBuds || !refused else { return self.showTagRename(from, to: to, buds: buds, plan: plan, refused: true, undo: nil) }
                let ticked = self.canvasFacets
                self.renameFacets(from, to: to)
                self.renameDeletedLenses(from, to: to, into: lenses)
                lenses.rows = self.canvasFacets
                let undo: @Sendable () -> Void = { [weak self] in
                    Task { @MainActor () async -> Void in
                        guard let self else { return }
                        if reachesBuds { self.undoRenameTag(edits) }
                        // Each lens it reached goes back, unless it has been changed since.
                        await self.settle()
                        self.undoRenameTagInLenses(lenses)
                        // The rows go back as they were, unless they have been changed since.
                        if self.canvasFacets.map(\.name) == lenses.rows.map(\.name) {
                            let rows = LensFacet.synced(ticked, with: self.savedLenses) ?? ticked
                            self.canvasFacets = rows
                            self.canvasLens = LensFacet.query(of: rows)
                        }
                    }
                }
                self.showTagRename(from, to: to, buds: buds, plan: plan, refused: refused, undo: undo)
            }
        }
        if reachesBuds {
            write { [self] vault in
                do {
                    let records = try await vault.renameTag(from, to: to)
                    edits.byID = Dictionary(records.map { (book.id(for: $0.path), $0) }) { a, _ in a }
                } catch {
                    // The buds go back with the reload; nothing else was touched.
                    toasts.show(Undoable(message: "Couldn't rename #\(from) to #\(to)", systemImage: "exclamationmark.triangle"))
                    throw error
                }
                done()
            }
        } else {
            // Only lenses: nothing in the tree changes, so nothing reloads.
            writeBeside({ _ in done() }, failed: {})
        }
    }

    /// The tag rename's toast, when it reached anything on show: deleted lenses alone are
    /// nothing to show.
    private func showTagRename(_ from: String, to: String, buds: Int, plan: SavedLens.TagRename, refused: Bool, undo: (@Sendable () -> Void)?) {
        guard buds > 0 || plan.asked > 0 else { return }
        let message = SavedLens.tagRenameMessage(
            from: from, to: to, buds: buds, lenses: plan.asked, alike: plan.alike, lensesRefused: refused
        )
        toasts.show(Undoable(message: message, systemImage: refused ? "exclamationmark.triangle" : "number", undo: undo))
    }
    /// A ticked tag the rename reached takes its new name, so its chip keeps matching; one that
    /// lands on a tag ticked already merges into it.
    private func renameFacets(_ from: String, to: String) {
        var seen: Set<LensFacet> = []
        let renamed = canvasFacets.map { facet -> LensFacet in
            guard case .tag(let tag) = facet, let new = BudTags.renamed(tag, from: from, to: to) else { return facet }
            return .tag(new)
        }.filter { seen.insert($0).inserted }
        if renamed.map(\.name) != canvasFacets.map(\.name) { canvasFacets = renamed }
    }

    /// Puts back each file a tag rename wrote, where nothing has changed it since. It queues
    /// behind the rename, so the vault's list of what it wrote is there by then.
    private func undoRenameTag(_ edits: TagEdits) {
        write { [self] vault in
            for (id, record) in edits.byID {
                _ = try? await vault.restoreText(path(id), from: record.after, to: record.before)
            }
        }
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
        commit { $0.trash(id, at: now) }
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
        savedLens = nil
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
        } else if tree.ancestors(of: id).contains(warehouseID) {
            openWarehouse()
        } else if inFiles {
            openAsFile(id)
        } else {
            center = id
            surface = .canvas
        }
    }

    /// Go anywhere to a destination: a place or a lens is a page in Files; Everything is the
    /// root, centered on the canvas or opened as the page in Files, the way a bud is. Either
    /// way a quiet view gives way to one that shows the pick.
    public func go(to destination: Destination, inFiles: Bool) {
        switch destination {
        case .everything: go(to: rootID, inFiles: inFiles)
        case .inbox: openInbox()
        case .archive: openArchive()
        case .trash: openTrash()
        case .today: open(.today)
        case .todos: open(.todos)
        case .pinned: open(.pinned)
        }
    }

    /// A row of Go anywhere: a bud that matched, or one of the places and lenses.
    public enum Pick: Hashable, Sendable {
        case bud(UUID)
        case destination(Destination)
    }

    /// Where Go anywhere lands on the row chosen, from the window or the desktop alike: a bud
    /// or a destination, each the way it goes above.
    public func go(_ pick: Pick, inFiles: Bool) {
        switch pick {
        case .bud(let id): go(to: id, inFiles: inFiles)
        case .destination(let destination): go(to: destination, inFiles: inFiles)
        }
    }

    /// The Files view on the Inbox.
    public func openInbox() { open(.inbox) }
    public func openArchive() { open(.archive) }
    public func openTrash() { open(.trash) }
    public func openWarehouse() { open(.warehouse) }
    public func openTriggers() { open(.triggers) }

    // MARK: the Library

    /// Keeps a bud and what is inside it in the Warehouse as a template.
    @discardableResult
    public func keepAsTemplate(_ id: UUID) -> Bool {
        move(id, under: warehouseID)
    }

    /// Stamps a copy of a template, with everything inside it, as the last child of `parent`. The
    /// copy carries `from: tpl/<template>/<when>`, which also keeps one occurrence from being
    /// stamped twice: a key planted before goes to the copy already there. A to-do starts open.
    @discardableResult
    public func stamp(_ template: UUID, into parent: UUID, key: String? = nil, at when: Date? = nil) -> Bud? {
        guard let top = tree.bud(template), tree.ancestors(of: template).contains(warehouseID) else { return nil }
        let now = when ?? self.now
        let from = key ?? Tree.stampKey(top.text, at: now)
        if let copy = tree.planted(from: from) { return copy }
        let inside = tree.walk(under: template)
        var copies: [UUID: UUID] = [template: UUID()]
        for bud in inside { copies[bud.id] = UUID() }
        var made: Bud?
        commit { tree in
            made = tree.plant(top.text, todo: top.isTodo, under: parent, from: from, id: copies[template]!, created: now)
            if !top.body.isEmpty { tree.setBody(copies[template]!, top.body) }
            for bud in inside {
                guard let id = copies[bud.id], let up = copies[bud.parent] else { continue }
                _ = tree.add(bud.text, todo: bud.isTodo, under: up, id: id, created: now)
                if !bud.body.isEmpty { tree.setBody(id, bud.body) }
            }
        }
        guard let made else { return nil }
        write { [self] vault in
            let planting = try await vault.plant(
                parent: parentPath(parent), title: top.text, kind: top.isTodo ? .todo : .note, from: from,
                preferredPath: made.id.uuidString
            )
            book.learn(made.id, at: planting.path)
            guard planting.new else { return }
            if !top.body.isEmpty { try await vault.setBody(planting.path, top.body) }
            for bud in inside {
                guard let id = copies[bud.id], let up = copies[bud.parent] else { continue }
                let file = try await vault.create(
                    parent: path(up), title: bud.text, kind: bud.isTodo ? .todo : .note, source: nil, preferredPath: id.uuidString
                )
                book.learn(id, at: file)
                if !bud.body.isEmpty { try await vault.setBody(file, bud.body) }
            }
        }
        lastPlanted = Planted(id: made.id, at: now)
        toasts.show(Undoable(message: "Stamped \(top.text) into \(tree.title(of: parent))") { [weak self] in
            Task { @MainActor in self?.remove(made.id) }
        })
        return made
    }


    public func back() {
        guard center != rootID else { return }
        center = tree.parent(of: center) ?? rootID
    }

    // MARK: commands

    /// The command run last, so the surface that owns the rest of its work can follow it.
    @Published public private(set) var lastCommand: Performed? = nil
    private var performed = 0

    public struct Performed: Equatable, Sendable {
        public let command: Command.ID
        /// The bud the command was given, when the key was pressed over one.
        public let bud: UUID?
        /// Counts up, so the same command twice is two changes.
        public let serial: Int
    }

    /// The bud whose page Files shows; nil on the canvas, a lens, a place or Everything.
    public var page: UUID? {
        guard surface == .files, lens == nil, place == nil, savedLens == nil, center != rootID, tree.bud(center) != nil else { return nil }
        return center
    }

    /// Whether a command can run now: while the shortcuts sheet records a key every key is the
    /// recorder's, so nothing runs and the menu bar greys out; a card over the window takes
    /// every key, the shortcuts sheet letting only its own through to close it; then the scope
    /// must hold on what the window shows. New under this needs a target as well, which the
    /// canvas always has and Files only on a bud's page; Close or reopen needs a to-do's page.
    public func allows(_ id: Command.ID) -> Bool {
        guard keys.recording == nil else { return false }
        guard modal == nil || (modal == .shortcuts && id == .shortcuts) else { return false }
        switch id {
        case .newUnderThis: return surface == .canvas || page != nil
        case .closeOrReopen: return page.flatMap { tree.bud($0) }?.isTodo == true
        default: break
        }
        switch Command.of(id).scope {
        case .everywhere: return true
        case .canvas: return surface == .canvas
        case .files: return surface == .files
        case .document: return page != nil
        }
    }

    /// The one way a command runs, from its key or the menu bar: nothing fires outside its scope,
    /// and a row that acts in place is not the store's to run. The store does its part (a modal,
    /// a surface, a tick) and notes the command, so the surface finishes what only it can: open
    /// the lit card, step through the matches, read instead of edit. `bud` is the one the key was
    /// pressed over, when the view knows: the lit card on the canvas, the page in Files. Open
    /// needs one; New under this takes the center when nothing is lit. Returns whether the
    /// command fired.
    @discardableResult
    public func perform(_ id: Command.ID, on bud: UUID? = nil) -> Bool {
        guard allows(id), !Command.of(id).inPlace else { return false }
        switch id {
        case .goAnywhere, .goAnywhereDesktop: searching = true
        case .capture: modal = .capture
        case .canvas, .files, .board, .calendar: if let view = id.surface { surface = view }
        case .shortcuts: modal = modal == .shortcuts ? nil : .shortcuts
        case .newUnderThis: modal = .adding(under: bud ?? page ?? center)
        case .open: guard bud != nil else { return false }
        case .soil: soilFolded.toggle()
        case .closeOrReopen: tick(bud ?? center)
        case .back, .nextMatch, .previousMatch, .read: break
        case .undo, .rowDown, .rowUp, .choose, .openInFiles, .close, .nest, .rise, .linkAsTyped: return false
        }
        performed += 1
        lastCommand = Performed(command: id, bud: bud, serial: performed)
        return true
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
        regroup()
    }

    /// The lens reads the tree alone, so a new center leaves it as it is.
    /// What a lens row is called now: a linked bud by its title today, the one it had when it was
    /// picked once it is gone.
    public func facetName(_ facet: LensFacet) -> String {
        if case .linked(let id, _) = facet, let bud = tree.bud(id) { return "Linked to \(bud.text)" }
        if case .saved(let lens) = facet, let now = saved(lens.id) { return now.name }
        return facet.name
    }

    /// A linked row whose bud is neither in the tree nor in the Trash (deleted, or renamed into a
    /// new file elsewhere) can match nothing again, so it goes.
    private func dropGoneFacets() {
        let gone = canvasFacets.filter { facet in
            guard case .linked(let id, _) = facet, tree.bud(id) == nil else { return false }
            return !tree.trashed.contains { $0.buds.contains { $0.id == id } }
        }
        if !gone.isEmpty { canvasFacets.removeAll { gone.contains($0) } }
    }

    private func relight() {
        canvasLight = canvasLens?.light(tree, links: links, on: now) ?? [:]
    }
}

/// The saved lenses a tag rename reached, saved and deleted, each before and after, filled in
/// once the vault has renamed the tag, for the undo.
@MainActor
private final class LensTagRename {
    var saved: [(before: SavedLens, after: SavedLens)] = []
    var deleted: [(before: SavedLens, after: SavedLens)] = []
    /// The ticked rows once the rename was done, so its undo knows whether they changed since.
    var rows: [LensFacet] = []
}

/// What a tag rename or remove wrote, by bud, filled in once the vault has done it, for the undo.
@MainActor
private final class TagEdits {
    var byID: [UUID: TagEditRecord] = [:]
}
// MARK: the Library's triggers

extension BudStore {
    /// This install, as a trigger's holder names it: the same id the soil's leases use.
    nonisolated public static var deviceID: String {
        let defaults = UserDefaults.standard
        if let known = defaults.string(forKey: SourceStore.deviceKey) { return known }
        let made = UUID().uuidString
        defaults.set(made, forKey: SourceStore.deviceKey)
        return made
    }

    /// Reads the triggers from the vault, oldest first, once the writes queued here have landed.
    /// Each trigger is two entries: its settings under its id, and who fires it with its log
    /// under `<id>#fired`, so an edit on one device and a firing on another both stand.
    public func reloadTriggers() async {
        await settle()
        guard let stored = try? await vault.shared(.triggers) else { return }
        var loaded: [Trigger] = []
        for (key, text) in stored where !key.hasSuffix(Self.firedSuffix) {
            guard var trigger = try? Self.triggerDecoder.decode(Trigger.self, from: Data(text.utf8)) else { continue }
            if let fired = stored[key + Self.firedSuffix],
               let state = try? Self.triggerDecoder.decode(Fired.self, from: Data(fired.utf8)) {
                trigger.holder = state.holder
                trigger.holderName = state.holderName
                trigger.log = state.log
            }
            loaded.append(trigger)
        }
        loaded.sort { ($0.created, $0.id) < ($1.created, $1.id) }
        if loaded != triggers { triggers = loaded }
    }

    /// Adds a trigger or changes its settings, here and in the vault; a new one brings who fires it.
    public func save(_ trigger: Trigger) {
        let isNew = !triggers.contains { $0.id == trigger.id }
        if let i = triggers.firstIndex(where: { $0.id == trigger.id }) {
            // Who fires it and its log are the firing's to change.
            var kept = trigger
            kept.holder = triggers[i].holder
            kept.holderName = triggers[i].holderName
            kept.log = triggers[i].log
            triggers[i] = kept
        } else {
            triggers.append(trigger)
        }
        var settings = trigger
        settings.holder = nil
        settings.holderName = nil
        settings.log = []
        guard let text = Self.triggerText(settings) else { return }
        write { vault in try await vault.setShared(.triggers, trigger.id, text) }
        if isNew { record(trigger) }
    }

    /// Writes who fires a trigger and its log, and nothing of its settings.
    private func record(_ trigger: Trigger) {
        if let i = triggers.firstIndex(where: { $0.id == trigger.id }) {
            triggers[i].holder = trigger.holder
            triggers[i].holderName = trigger.holderName
            triggers[i].log = trigger.log
        }
        guard let text = Self.triggerText(Fired(holder: trigger.holder, holderName: trigger.holderName, log: trigger.log)) else { return }
        write { vault in try await vault.setShared(.triggers, trigger.id + Self.firedSuffix, text) }
    }

    public func deleteTrigger(_ id: String) {
        triggers.removeAll { $0.id == id }
        write { vault in
            try await vault.setShared(.triggers, id, nil)
            try await vault.setShared(.triggers, id + Self.firedSuffix, nil)
        }
    }

    /// Who fires a trigger and what it fired, kept apart from its settings.
    private struct Fired: Codable {
        var holder: String?
        var holderName: String?
        var log: [Trigger.Firing]
    }

    private static let firedSuffix = "#fired"

    private static var triggerDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func triggerText(_ value: some Encodable) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) }
    }

    /// The vault path a copy goes into for a place on screen: nil for Everything.
    public func triggerPath(of place: UUID) -> String? { parentPath(place) }

    /// The place a trigger stamps into, when it is still there.
    func place(of trigger: Trigger) -> UUID? {
        guard let into = trigger.into else { return rootID }
        if into == vault.inboxPath { return inboxID }
        let id = book.id(for: into)
        return tree.bud(id) == nil ? nil : id
    }

    /// Fires every trigger due on this device now: stamps its template into its place for the
    /// occurrence, or logs why it could not, and keeps the trigger on this device.
    public func fireTriggers(now: Date? = nil, device: String = BudStore.deviceID, calendar: Calendar? = nil) {
        let now = now ?? self.now
        let calendar = calendar ?? self.calendar
        for trigger in triggers {
            guard let occurrence = trigger.due(at: now, device: device, calendar: calendar) else { continue }
            var skipped: String?
            if let template = tree.templates().first(where: { $0.text == trigger.template }) {
                if let place = place(of: trigger) {
                    stamp(template.id, into: place, key: Tree.stampKey(template.text, at: occurrence), at: occurrence)
                } else {
                    skipped = "\(trigger.intoName) is gone"
                }
            } else {
                skipped = "no template \(trigger.template) in the Warehouse"
            }
            record(trigger.fired(occurrence, device: device, deviceName: Self.deviceName, skipped: skipped))
        }
    }

    /// Checks the triggers every minute while the app runs.
    public func startTriggers() {
        guard firing == nil else { return }
        firing = Task { [weak self] in
            while !Task.isCancelled {
                await self?.reloadTriggers()
                self?.fireTriggers()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}

// MARK: the panels' layout

extension BudStore {
    /// The one key of the layout map: which panels each sidebar holds, as JSON.
    static let layoutKey = "panels"

    /// Changes the panels. One that moves or hides a panel goes to the vault too, so every
    /// device shows the same arrangement; folding one stays here.
    public func arrange(_ change: (inout PanelState) -> Void) {
        let before = panels.layout
        change(&panels)
        guard panels.layout != before, let text = Self.triggerText(panels.layout) else { return }
        layoutEdits += 1
        write { vault in try await vault.setShared(.layout, Self.layoutKey, text) }
    }

    /// Reads the layout from the vault, once the writes queued here have landed: after a sync
    /// brought another device's arrangement.
    public func reloadLayout() async {
        await reread(.layout, edits: \.layoutEdits) { stored in
            guard let text = stored[Self.layoutKey],
                  let layout = try? Self.triggerDecoder.decode(PanelLayout.self, from: Data(text.utf8)) else { return }
            if layout != panels.layout { panels.layout = layout }
        }
    }
}

// MARK: the boards' columns

extension BudStore {
    /// The board of the center bud, with the tag columns the vault keeps for it.
    public var board: Board { board(of: center) }

    /// The columns are `boardColumns(of:)`, stored or the default, so the board and its
    /// edits read one list.
    public func board(of id: UUID) -> Board {
        Board(tree: tree, center: id, tags: boardColumns(of: id).tags)
    }

    /// Sets which tag columns a bud's board shows, in order; nil goes back to the tags in use.
    /// The list goes to the vault under the bud's id, so every device shows the same board.
    public func setBoardColumns(_ columns: BoardColumns?, of id: UUID) {
        guard boards[id] != columns else { return }
        boards[id] = columns
        boardEdits += 1
        let text = columns.flatMap(Self.triggerText)
        write { vault in try await vault.setShared(.board, id.uuidString, text) }
    }

    /// Reads every board's columns from the vault, once the writes queued here have landed:
    /// after a sync brought another device's.
    public func reloadBoards() async {
        await reread(.board, edits: \.boardEdits) { stored in
            var loaded: [UUID: BoardColumns] = [:]
            for (key, text) in stored {
                guard let id = UUID(uuidString: key),
                      let columns = try? Self.triggerDecoder.decode(BoardColumns.self, from: Data(text.utf8)) else { continue }
                loaded[id] = columns
            }
            if loaded != boards { boards = loaded }
        }
    }

    /// What is known of a bud's picture; `.unknown` until `loadPicture` has asked the vault.
    public func pictureState(of id: UUID) -> BoardPictureState {
        pictures[id] ?? .unknown
    }

    /// Asks the vault for the bud's first picture once and keeps the answer, picture or none,
    /// decoded no larger than a card's slot; asking again changes nothing. A card calls it
    /// when it appears unknown.
    public func loadPicture(of id: UUID) async {
        guard pictures[id] == nil else { return }
        await pending?.value
        let data = try? await vault.picture(of: path(id))
        guard pictures[id] == nil else { return }
        pictures[id] = data.flatMap { BoardPicture.decode($0) }.map { .picture($0) } ?? BoardPictureState.none
    }

    /// Puts a picture in the cache without asking the vault: a still picture fills it before
    /// the page is drawn, since the drawing cannot wait for a load. Nil keeps "none".
    public func keepPicture(_ picture: BoardPicture?, of id: UUID) {
        pictures[id] = picture.map { .picture($0) } ?? BoardPictureState.none
    }

    /// Forgets the pictures, so the cards ask the vault again: after its files changed under
    /// the app.
    public func forgetPictures() {
        if !pictures.isEmpty { pictures = [:] }
    }
}

// MARK: saved lenses

extension BudStore {
    /// One saved lens, while the vault still holds it.
    public func saved(_ id: UUID) -> SavedLens? {
        savedLenses.first { $0.id == id }
    }

    /// Keeps the canvas lens, or `query`, under a name, and offers to take it back. Nothing is
    /// kept for an empty name, for no question, for one nothing can answer, or for one a saved
    /// lens asks already: `SavedLens.refusal` says which.
    @discardableResult
    public func saveLens(_ name: String, query: LensQuery? = nil) -> SavedLens? {
        let query = query ?? canvasLens
        guard SavedLens.refusal(name: name, query: query, saved: savedLenses) == nil,
              let name = SavedLens.clean(name), let query else { return nil }
        let lens = SavedLens(name: name, query: query)
        keep(lens)
        toasts.show(Undoable(message: "Saved \(name)", systemImage: "line.3.horizontal.decrease.circle") { [weak self] in
            Task { @MainActor in
                // Only the lens as it was saved: one renamed or changed since stays.
                guard let self, self.saved(lens.id) == lens else { return }
                self.drop(lens.id)
            }
        })
        return lens
    }

    /// Gives a saved lens a new name and offers the old one back.
    public func renameLens(_ id: UUID, to name: String) {
        guard var lens = saved(id), let name = SavedLens.clean(name), name != lens.name else { return }
        let before = lens
        lens.name = name
        keep(lens)
        toasts.show(Undoable(message: "Renamed \(before.name) to \(name)", systemImage: "line.3.horizontal.decrease.circle") { [weak self] in
            Task { @MainActor in
                // The name alone goes back, while the lens is still there under the new one:
                // its question keeps any tag rename made since.
                guard let self, var now = self.saved(id), now.name == name else { return }
                now.name = before.name
                self.keep(now)
            }
        })
    }

    /// Lets a saved lens go and offers to keep it again, under the same id.
    public func deleteLens(_ id: UUID) {
        guard let lens = saved(id) else { return }
        let at = canvasFacets.firstIndex(of: .saved(lens))
        drop(id)
        // The rows left once it went: its row comes back only to these, where it was.
        let left = canvasFacets
        deletedLenses = Array((deletedLenses.filter { $0.id != id } + [lens]).suffix(Self.deletedLensesKept))
        toasts.show(Undoable(message: "Deleted \(lens.name)") { [weak self] in
            Task { @MainActor in
                // As it would be now, tag renames and all; not over a lens that asks the same
                // question, saved since.
                guard let self, let lens = self.deletedLenses.first(where: { $0.id == id }) else { return }
                self.deletedLenses.removeAll { $0.id == id }
                guard self.saved(id) == nil,
                      !self.savedLenses.contains(where: { $0.asksSame(as: lens) }) else { return }
                self.keep(lens)
                if let at, self.canvasFacets == left, self.canvasFacets.map(\.name) == left.map(\.name) {
                    self.canvasFacets.insert(.saved(lens), at: min(at, left.count))
                }
            }
        })
    }
    /// Asks the canvas a saved lens's question, exactly as it was saved, in place of the rows
    /// ticked; asked again while ticked, its row alone is unticked. A bud it is linked with that
    /// has gone keeps matching nothing rather than dropping out of the question.
    public func applyLens(_ id: UUID) {
        guard let lens = saved(id) else { return }
        if canvasFacets.contains(.saved(lens)) {
            canvasFacets.removeAll { $0 == .saved(lens) }
        } else {
            canvasFacets = [.saved(lens)]
        }
    }

    /// The Files view on a saved lens.
    public func open(saved id: UUID) {
        guard saved(id) != nil else { return }
        savedLens = id
        surface = .files
    }

    /// Reads every saved lens from the vault, once the writes queued here have landed: after a
    /// sync brought another device's. A page on a lens that is gone closes.
    /// A read that a change made here overtook is read again once that change has landed.
    public func reloadLenses() async {
        await reread(.lenses, edits: \.lensEdits, apply: applyLenses)
    }

    private func applyLenses(_ stored: [String: String]) {
        let loaded = SavedLens.read(stored)
        if loaded != savedLenses { savedLenses = loaded }
        if let open = savedLens, saved(open) == nil { savedLens = nil }
    }

    /// What the open saved lens finds, again.
    private func regroup() {
        let found = savedLens.flatMap(saved)?.query.hitsByThread(tree, links: links, on: now) ?? []
        if found != savedLensThreads { savedLensThreads = found }
    }

    /// A tag rename reaches the saved lenses that ask for the tag, here and in the vault, and
    /// the deleted ones an Undo may bring back; a lens a newer build wrote stays as it is, and
    /// every lens stays, even two that now ask one question. What each was before and after
    /// goes into `rename`, for the undo.
    private func renameTagInLenses(
        _ from: String, to: String, into rename: LensTagRename,
        landed: @escaping @MainActor (SavedLens.TagRename, _ refused: Bool) -> Void
    ) {
        let plan = SavedLens.afterTagRename(savedLenses, from: from, to: to)
        rename.saved = plan.renamed
        // Every change goes to the vault in one write.
        var changes: [(key: String, text: String)] = []
        for pair in plan.renamed {
            guard let text = pair.after.text else { continue }
            savedLenses = SavedLens.sorted(savedLenses.filter { $0.id != pair.after.id } + [pair.after])
            changes.append((pair.after.id.uuidString, text))
        }
        guard !changes.isEmpty else { return landed(plan, false) }
        lensEdits += 1
        writeBeside({ vault in
            for change in changes { try await vault.setShared(.lenses, change.key, change.text) }
            landed(plan, false)
        }) { [weak self] in
            // Refused: one read puts the lenses back as the vault holds them.
            self?.queueReread(.lenses, edits: \.lensEdits) { self?.applyLenses($0) }
            landed(plan, true)
        }
    }

    /// The deleted lenses an Undo may bring back follow a tag rename too, so one comes back
    /// asking what the others ask.
    private func renameDeletedLenses(_ from: String, to: String, into rename: LensTagRename) {
        deletedLenses = deletedLenses.map { lens in
            guard let renamed = lens.renamingTag(from, to: to) else { return lens }
            rename.deleted.append((lens, renamed))
            return renamed
        }
    }
    /// Takes a tag rename back from the lenses it reached, each one unless it changed since.
    private func undoRenameTagInLenses(_ rename: LensTagRename) {
        for (before, after) in rename.saved where saved(after.id) == after { keep(before) }
        deletedLenses = deletedLenses.map { lens in
            rename.deleted.first { $0.after == lens }?.before ?? lens
        }
    }

    /// The canvas follows the saved lenses: one that is gone drops out of the ticked rows, and
    /// one that changed asks as it is now.
    private func syncSavedFacets() {
        guard let synced = LensFacet.synced(canvasFacets, with: savedLenses) else { return }
        canvasFacets = synced
        // The rows are the same rows, so the question is worked out here.
        canvasLens = LensFacet.query(of: synced)
    }

    /// A lens that cannot be written as text changes nothing, here or in the vault.
    private func keep(_ lens: SavedLens) {
        guard let text = lens.text else { return }
        lensEdits += 1
        savedLenses = SavedLens.sorted(savedLenses.filter { $0.id != lens.id } + [lens])
        writeLens(lens.id.uuidString, text)
    }

    private func drop(_ id: UUID) {
        guard saved(id) != nil else { return }
        lensEdits += 1
        savedLenses.removeAll { $0.id == id }
        if savedLens == id { savedLens = nil }
        writeLens(id.uuidString, nil)
    }

    /// One saved lens to the vault. One the vault refuses sends the list back to what the vault
    /// holds, in the queue, so it is back before `settle` returns.
    private func writeLens(_ key: String, _ text: String?) {
        writeBeside({ vault in try await vault.setShared(.lenses, key, text) }) { [weak self] in
            self?.queueReread(.lenses, edits: \.lensEdits) { self?.applyLenses($0) }
        }
    }
}

// MARK: dropping a card on a column

extension BudStore {
    /// Drops a card of the center bud's board on one of its columns and, once the vault has
    /// written it, offers to take it back. Only the bud's front matter changes, as `BoardDrop`
    /// spells out: its tags, its state, its cancelled mark. A card that sits there already, or
    /// a bud that is not on this board, stays as it is; a drop `BoardDrop.refusal` turns down
    /// says why in a toast; closing a bud with open to-dos inside asks first, through the Close
    /// branch dialog, as a tick does. Returns whether the card moved.
    @discardableResult
    public func drop(_ id: UUID, on column: BoardColumn.Kind) -> Bool {
        let columns = board.columnTags
        guard board.card(id) != nil, let before = tree.bud(id),
              let drop = BoardDrop.of(before, on: column, columns: columns) else { return false }
        if let refusal = BoardDrop.refusal(of: before, on: column, columns: columns) {
            toasts.show(Undoable(message: refusal, systemImage: "exclamationmark.triangle"))
            return false
        }
        if drop.state == .done, tree.openCount(under: id) > 0 {
            modal = .closeBranch(id: id)
            return false
        }
        commit { $0.apply(drop, to: id) }
        write { [self] _ in
            do {
                try await edit(id) { try await drop.write(to: $0, at: $1) }
            } catch {
                toasts.show(Undoable(message: BoardDrop.failure(on: column, title: before.text), systemImage: "exclamationmark.triangle"))
                return
            }
            toasts.show(Undoable(message: BoardDrop.message(on: column, title: before.text)) { [weak self] in
                Task { @MainActor in self?.undoDrop(id, drop, before: before) }
            })
        }
        return true
    }

    /// Takes the drop back, here and in the vault: what it wrote goes back as it was, and what
    /// changed since stays.
    private func undoDrop(_ id: UUID, _ drop: BoardDrop, before: Bud) {
        commit { $0.undo(drop, on: id, before: before) }
        write { [self] _ in try await edit(id) { try await drop.undo(to: $0, at: $1, before: before) } }
    }
}

#endif
