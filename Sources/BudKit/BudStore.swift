#if canImport(SwiftUI)
import Foundation
import Combine
import SwiftUI

/// The tree, the current center of the web, and the layout derived from both.
/// Every mutation saves to disk; the layout is recomputed once per change, not per frame.
@MainActor
public final class BudStore: ObservableObject {
    @Published public private(set) var tree: Tree
    @Published public private(set) var layout: Layout
    @Published public var center: UUID {
        didSet { if center != oldValue { relayout() } }
    }

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
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Bud", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("buds.json")
    }

    public var centerTrail: [UUID] { Array(tree.ancestors(of: center).reversed()) + [center] }

    public func add(_ text: String, todo: Bool, under parent: UUID) {
        commit { $0.add(text, todo: todo, under: parent) }
    }

    public func update(_ id: UUID, text: String, todo: Bool) {
        commit { $0.update(id, text: text, todo: todo) }
    }

    public func toggle(_ id: UUID) {
        commit { $0.toggle(id) }
    }

    public func remove(_ id: UUID) {
        commit { $0.remove(id) }
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
