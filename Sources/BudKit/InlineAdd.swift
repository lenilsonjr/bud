import Foundation

/// The inline bar on the canvas: where the next line lands, which kind it is, and the way back up
/// after going down a level. Pure so it tests on its own; the canvas draws it and plants through
/// the store.
public struct InlineAdd: Equatable, Sendable {
    /// The bud the next line plants under.
    public private(set) var parent: UUID
    /// Whether the next line is a to-do; a note otherwise.
    public var todo: Bool
    public var text: String = ""
    /// The bud planted last at this level, the one Tab goes down into.
    public private(set) var last: UUID?
    /// The parents above this level, nearest last, for going back up.
    public private(set) var trail: [UUID] = []

    public init(under parent: UUID, todo: Bool) {
        self.parent = parent
        self.todo = todo
    }

    /// The line as it would be planted: trimmed, nil when there is nothing to plant.
    public var line: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A line was planted: the bar empties and stays on the same level for the next one.
    public mutating func planted(_ id: UUID) {
        last = id
        text = ""
    }

    /// Down a level, under the bud planted last. False when nothing has been planted here yet.
    @discardableResult
    public mutating func nest(todo: Bool) -> Bool {
        guard let last else { return false }
        trail.append(parent)
        parent = last
        self.last = nil
        self.todo = todo
        return true
    }

    /// Back up a level; the bud this level hung from becomes the one Tab goes down into again.
    @discardableResult
    public mutating func rise(todo: Bool) -> Bool {
        guard let up = trail.popLast() else { return false }
        last = parent
        parent = up
        self.todo = todo
        return true
    }

    public var canNest: Bool { last != nil }
    public var canRise: Bool { !trail.isEmpty }

    /// The card the bar sits under: the parent when the canvas shows it, else the nearest
    /// ancestor it shows. Nil when none of them is on the canvas.
    public func anchor(in layout: Layout, tree: Tree) -> UUID? {
        ([parent] + tree.ancestors(of: parent)).first { layout.cards[$0] != nil }
    }

    /// The bar's placeholder: "Add under Launch the newsletter", "Add a thread" on Everything.
    public func placeholder(in tree: Tree) -> String {
        parent == rootID ? "Add a thread" : "Add under \(tree.title(of: parent))"
    }
}
