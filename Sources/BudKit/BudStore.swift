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

/// The tree, the current center of the web, and the layout derived from both.
/// Every mutation saves to disk; the layout is recomputed once per change, not per frame.
@MainActor
public final class BudStore: ObservableObject {
    @Published public private(set) var tree: Tree
    @Published public private(set) var layout: Layout
    @Published public var center: UUID {
        didSet {
            if center != oldValue {
                relayout()
                lens = nil
                inboxOpen = false
            }
        }
    }
    /// Whether Files shows the Inbox instead of the center's page; a change of center clears it.
    @Published public var inboxOpen = false
    @Published public var surface: Surface = .canvas
    /// The lens Files shows instead of the center's page; a change of center clears it.
    @Published public var lens: Lens? = nil {
        didSet { if lens != nil { inboxOpen = false } }
    }
    /// The canvas scale: 1 is 100%. Pinch changes it; the zoom control in the bar resets it.
    @Published public var zoom: CGFloat = 1
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

    private let fileURL: URL?

    public init(fileURL: URL? = BudStore.defaultFile) {
        self.fileURL = fileURL
        var loaded: Tree? = nil
        if let url = fileURL, let data = try? Data(contentsOf: url) {
            loaded = try? JSONDecoder().decode(Tree.self, from: data)
        }
        let tree = loaded ?? Tree.seed()
        self.tree = tree
        self.center = rootID
        self.layout = LayoutEngine.layout(of: tree, center: rootID)
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
        lastPlanted = Planted(id: id, at: Date())
        toasts.show(Undoable(message: "Planted under \(tree.title(of: parent))") { [weak self] in
            Task { @MainActor in self?.remove(id) }
        })
        return planted
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
        lastPlanted = Planted(id: id, at: Date())
        toasts.show(Undoable(message: "Captured to the Inbox") { [weak self] in
            Task { @MainActor in self?.remove(id) }
        })
        return captured
    }

    /// Gives a bud and its branch a new parent and offers to move it back. A move the tree
    /// refuses (under itself or its own descendant) does nothing and says nothing.
    @discardableResult
    public func move(_ id: UUID, under parent: UUID) -> Bool {
        guard let from = tree.bud(id)?.parent else { return false }
        var moved = false
        commit { moved = $0.move(id, under: parent) }
        guard moved else { return false }
        toasts.show(Undoable(message: "Moved to \(tree.title(of: parent))") { [weak self] in
            Task { @MainActor in self?.commit { $0.move(id, under: from) } }
        })
        return true
    }

    public func update(_ id: UUID, text: String, todo: Bool) {
        commit { $0.update(id, text: text, todo: todo) }
    }

    /// What every checkbox calls. A done to-do reopens at once; an open to-do with nothing open
    /// inside closes at once; one with open to-dos inside asks first, through the Close branch
    /// dialog, since closing never cascades on its own.
    public func tick(_ id: UUID) {
        guard let bud = tree.bud(id), bud.isTodo else { return }
        if bud.isDone {
            commit { $0.toggle(id) }
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
        commit { changed = $0.close(id, cascade: cascade) }
        guard !changed.isEmpty else { return }
        let inside = changed.count - 1
        let message = inside == 0 ? "Closed \(title)" : "Closed \(title) and \(inside) inside"
        toasts.show(Undoable(message: message) { [weak self] in
            Task { @MainActor in self?.commit { $0.reopen(changed) } }
        })
    }

    public func toggle(_ id: UUID) {
        commit { $0.toggle(id) }
    }

    public func setBody(_ id: UUID, _ body: String) {
        commit { $0.setBody(id, body) }
    }

    public func setWhen(_ id: UUID, _ when: Date?) {
        commit { $0.setWhen(id, when) }
    }

    public func setDue(_ id: UUID, _ due: Date?) {
        commit { $0.setDue(id, due) }
    }

    public func setPinned(_ id: UUID, _ pinned: Bool) {
        commit { $0.setPinned(id, pinned) }
    }

    public func remove(_ id: UUID) {
        commit { $0.remove(id) }
    }

    /// Trashes a bud and its branch and offers to take it back; Undo restores the branch as it was.
    public func trash(_ id: UUID) {
        guard tree.bud(id) != nil else { return }
        let title = tree.title(of: id)
        var branch: [Bud] = []
        commit { branch = $0.trash(id) }
        toasts.show(Undoable(message: "Trashed \(title)") { [weak self] in
            Task { @MainActor in self?.commit { $0.restore(branch) } }
        })
    }

    /// Makes a note a to-do, open. A to-do stays what it is.
    public func makeTodo(_ id: UUID) {
        guard let bud = tree.bud(id), !bud.isTodo else { return }
        commit { $0.update(id, text: bud.text, todo: true) }
    }

    /// Open as file: the Files view with this bud as the page. The center is the selection there.
    public func openAsFile(_ id: UUID) {
        center = id
        lens = nil
        inboxOpen = false
        surface = .files
    }

    /// The Files view on a lens.
    public func open(_ lens: Lens) {
        self.lens = lens
        inboxOpen = false
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
    public func openInbox() {
        lens = nil
        inboxOpen = true
        surface = .files
    }

    public func back() {
        guard center != rootID else { return }
        center = tree.parent(of: center) ?? rootID
    }

    private func commit(_ change: (inout Tree) -> Void) {
        change(&tree)
        if center != rootID, tree.bud(center) == nil { center = rootID }
        relayout()
        save()
    }

    private func relayout() {
        layout = LayoutEngine.layout(of: tree, center: center)
    }

    private func save() {
        guard let url = fileURL, let data = try? JSONEncoder().encode(tree) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
#endif
