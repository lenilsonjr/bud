import Foundation

/// The buds a device kept in the old JSON file, brought into its vault once.
///
/// Setting the file aside, once its buds are in, is what marks it brought in, so the buds may
/// land in a vault that already holds others: a capture, a trigger or a bud added while the import waited. Names that
/// clash are the vault's to settle, as for any new bud.
public enum OldBuds {
    /// Where the file goes once its buds are in: `buds.imported.json`, or `buds.imported 2.json`
    /// and on when a file set aside before is still there, so none is written over.
    static func setAside(_ file: URL) -> URL {
        let stem = file.deletingPathExtension()
        let folder = stem.deletingLastPathComponent()
        let name = stem.lastPathComponent + ".imported"
        var aside = folder.appendingPathComponent(name + ".json")
        var number = 2
        while FileManager.default.fileExists(atPath: aside.path) {
            aside = folder.appendingPathComponent("\(name) \(number).json")
            number += 1
        }
        return aside
    }

    /// Plants the buds kept in `file` through `plant` and sets the file aside, once. The buds go
    /// in first and the file is set aside after, so a launch cut short in between plants them
    /// again beside the first ones rather than losing them; a plant that fails leaves the file
    /// for the next launch. The Apple TV's vault is a cache its peers fill, and a file that only
    /// holds the untouched sample world is set aside unplanted: two devices planting it would
    /// collide when they pair. A sample that was ticked, pinned, written in, moved or scheduled
    /// is the person's own and is planted. A file that is missing or will not read is left
    /// where it is.
    /// Returns whether anything was planted.
    public static func bring(
        from file: URL, platform: VaultPlatform, plant: ([BudRecord]) async throws -> Void
    ) async -> Bool {
        guard platform != .tvOS, let data = try? Data(contentsOf: file),
              let tree = try? JSONDecoder().decode(Tree.self, from: data)
        else { return false }
        let planted = !isSample(tree)
        if planted {
            do {
                try await plant(tree.records())
            } catch {
                NSLog("Bud: the old buds did not plant: \(error)")
                return false
            }
        }
        do {
            try FileManager.default.moveItem(at: file, to: setAside(file))
        } catch {
            NSLog("Bud: the old buds file stays where it was: \(error)")
        }
        return planted
    }

    /// Whether the tree is the sample world as it was made, by its shape.
    static func isSample(_ tree: Tree) -> Bool {
        shape(of: tree) == shape(of: Tree.seed())
    }

    /// What tells a person's buds from the untouched sample world: each bud's title, where it
    /// is (its place and the title above it), state, pin, body, and whether it has a day or a
    /// due date. The dates themselves are left out, since the sample's are set from the day it
    /// was made.
    static func shape(of tree: Tree) -> Set<String> {
        let records = tree.records().filter { $0.place != .trash }
        let titles = Dictionary(records.map { ($0.path, $0.title) }, uniquingKeysWith: { first, _ in first })
        return Set(records.map { record in
            [
                record.title, record.place.rawValue, record.parent.flatMap { titles[$0] } ?? "",
                record.state?.rawValue ?? "note", String(record.pinned), record.body,
                String(record.when != nil), String(record.due != nil),
            ].joined(separator: "\u{1F}")
        })
    }
}
