import Foundation

/// The one noun. A bud is text with a parent; what it *is* comes from what it carries:
/// no state → a note, a state → a to-do. Depth is unlimited and costs the same everywhere.
public let rootID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

public enum BudState: String, Codable, Sendable {
    case open, done
}

public struct Bud: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var text: String
    public var state: BudState?
    public var parent: UUID
    public var order: Double

    public init(id: UUID = UUID(), text: String, state: BudState? = nil, parent: UUID = rootID, order: Double = 0) {
        self.id = id
        self.text = text
        self.state = state
        self.parent = parent
        self.order = order
    }

    public var isTodo: Bool { state != nil }
    public var isDone: Bool { state == .done }
}

/// A plain value: every operation is a small mutation, so the store can persist after each one.
public struct Tree: Codable, Equatable, Sendable {
    public var buds: [Bud]

    public init(buds: [Bud] = []) {
        self.buds = buds
    }

    public func bud(_ id: UUID) -> Bud? {
        buds.first { $0.id == id }
    }

    public func children(of id: UUID) -> [Bud] {
        buds.filter { $0.parent == id }.sorted { ($0.order, $0.id.uuidString) < ($1.order, $1.id.uuidString) }
    }

    public func hasChildren(_ id: UUID) -> Bool {
        buds.contains { $0.parent == id }
    }

    /// nil for the root; the root for first-layer buds.
    public func parent(of id: UUID) -> UUID? {
        id == rootID ? nil : (bud(id)?.parent ?? rootID)
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
        id == rootID ? "Everything" : (bud(id)?.text ?? "")
    }

    public func descendants(of id: UUID) -> [UUID] {
        var out: [UUID] = []
        var stack = children(of: id).map(\.id)
        while let next = stack.popLast() {
            out.append(next)
            stack.append(contentsOf: children(of: next).map(\.id))
        }
        return out
    }

    public func openCount(under id: UUID) -> Int {
        descendants(of: id).compactMap(bud).filter { $0.state == .open }.count
    }

    /// Descendants in reading order: each bud before its children, siblings in their order.
    public func walk(under id: UUID) -> [Bud] {
        var out: [Bud] = []
        for child in children(of: id) {
            out.append(child)
            out.append(contentsOf: walk(under: child.id))
        }
        return out
    }

    /// The one open to-do to do next under a bud: the first in reading order. Dates come later.
    public func nextStep(under id: UUID) -> Bud? {
        walk(under: id).first { $0.state == .open }
    }

    @discardableResult
    public mutating func add(_ text: String, todo: Bool, under parent: UUID) -> Bud {
        let last = children(of: parent).last?.order ?? 0
        let bud = Bud(text: text, state: todo ? .open : nil, parent: parent, order: last + 1)
        buds.append(bud)
        return bud
    }

    public mutating func update(_ id: UUID, text: String, todo: Bool) {
        guard let i = buds.firstIndex(where: { $0.id == id }) else { return }
        buds[i].text = text
        if todo, buds[i].state == nil { buds[i].state = .open }
        if !todo { buds[i].state = nil }
    }

    public mutating func toggle(_ id: UUID) {
        guard let i = buds.firstIndex(where: { $0.id == id }), let state = buds[i].state else { return }
        buds[i].state = state == .done ? .open : .done
    }

    /// Removes a bud and its whole subtree.
    public mutating func remove(_ id: UUID) {
        let gone = Set(descendants(of: id) + [id])
        buds.removeAll { gone.contains($0.id) }
    }

    /// A small world to start from.
    public static func seed() -> Tree {
        var t = Tree()
        let newsletter = t.add("Launch the newsletter", todo: true, under: rootID)
        let name = t.add("Pick a name", todo: true, under: newsletter.id)
        t.add("Shortlist three candidates", todo: true, under: name.id)
        t.add("Ask two readers which one lands", todo: true, under: name.id)
        t.add("Short names read better in the inbox", todo: false, under: name.id)
        let sender = t.add("Set up the sender", todo: true, under: newsletter.id)
        t.add("Domain records are in the shared doc", todo: false, under: sender.id)
        t.add("Verify the address", todo: true, under: sender.id)
        let design = t.add("Design notes", todo: false, under: newsletter.id)
        t.add("Warm, not corporate", todo: false, under: design.id)
        t.add("First issue outline", todo: false, under: newsletter.id)
        let roadmap = t.add("Q4 roadmap", todo: true, under: rootID)
        t.add("Review the onboarding flow", todo: true, under: roadmap.id)
        t.add("Launch notes", todo: false, under: roadmap.id)
        let language = t.add("Learn a language", todo: true, under: rootID)
        t.add("Ten minutes a day", todo: true, under: language.id)
        let health = t.add("Health reset", todo: true, under: rootID)
        t.add("A walk before the first meeting", todo: true, under: health.id)
        t.add("Routines", todo: false, under: rootID)
        t.add("Gift ideas", todo: false, under: rootID)
        t.add("Side project", todo: false, under: rootID)
        return t
    }
}
