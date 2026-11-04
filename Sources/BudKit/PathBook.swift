import Foundation

/// Which bud each vault path names. A vault on disk names a bud by where its file is, so a rename,
/// a move or a trip to the Trash gives it a new path; the book keeps the bud's id across them, and
/// a path it has never seen gets the id derived from it.
public struct PathBook: Sendable, Equatable {
    private var paths: [UUID: String] = [:]
    private var ids: [String: UUID] = [:]

    public init() {}

    /// The path a bud has in the vault: the one last seen, else its id, the memory vault's way.
    public func path(of id: UUID) -> String { paths[id] ?? id.uuidString }

    /// The bud a path names.
    public func id(for path: String) -> UUID { ids[path] ?? Bud.id(forPath: path) }

    /// Remembers where a bud is.
    public mutating func learn(_ id: UUID, at path: String) {
        if let old = paths[id], ids[old] == id { ids[old] = nil }
        paths[id] = path
        ids[path] = id
    }

    /// A bud went from `old` to `new`, and every bud in its folder went with it.
    public mutating func move(from old: String, to new: String) {
        guard old != new else { return }
        let from = Self.folder(of: old) + "/"
        let to = Self.folder(of: new) + "/"
        let moved = ids.filter { $0.key == old || $0.key.hasPrefix(from) }
        for (path, id) in moved {
            learn(id, at: path == old ? new : to + path.dropFirst(from.count))
        }
    }

    /// Keeps exactly the buds a snapshot holds, each under its id.
    public mutating func keep(_ records: [BudRecord]) {
        var book = PathBook()
        for record in records { book.learn(id(for: record.path), at: record.path) }
        self = book
    }

    /// The folder that holds a bud's children: its path without the `.md`.
    static func folder(of path: String) -> String {
        path.hasSuffix(".md") ? String(path.dropLast(3)) : path
    }
}
