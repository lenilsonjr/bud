import XCTest
@testable import BudKit

/// The old JSON file brought into the vault: once, whatever reached the vault first.
final class OldBudsTests: XCTestCase {
    /// A fresh folder holding `buds.json` with `tree` in it.
    private func oldFile(_ tree: Tree) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("buds.json")
        try JSONEncoder().encode(tree).write(to: file)
        return file
    }

    /// The buds a person kept before the vault: a to-do with one bud under it, and a capture.
    private func kept() -> Tree {
        var tree = Tree()
        let seeds = tree.add("Order seed packets", todo: true, under: rootID)
        tree.add("Tomatoes and basil", todo: false, under: seeds.id)
        tree.capture("Borrow the long ladder", source: "iphone")
        return tree
    }

    /// Plants records into a memory vault, parents first, as the vault on disk does.
    private func planting(into vault: MemoryVault) -> ([BudRecord]) async throws -> Void {
        { records in
            var planted: [String: String] = [:]
            for record in records where record.place != .trash {
                let parent = record.parent.map { planted[$0] ?? $0 }
                planted[record.path] = try await vault.create(
                    parent: parent, title: record.title, kind: record.kind, source: record.source, preferredPath: nil
                )
            }
        }
    }

    private func titles(_ vault: MemoryVault) async throws -> Set<String> {
        Set(try await vault.snapshot().filter { $0.place != .trash }.map(\.title))
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func testTheOldBudsComeInAfterABudReachedTheVaultFirst() async throws {
        let file = try oldFile(kept())
        let vault = MemoryVault(tree: Tree())
        _ = try await vault.create(parent: nil, title: "Water the ferns", kind: .todo, source: "mac", preferredPath: nil)
        let planted = await OldBuds.bring(from: file, platform: .iOS, plant: planting(into: vault))
        XCTAssertTrue(planted)
        let titles = try await titles(vault)
        XCTAssertEqual(titles, ["Water the ferns", "Order seed packets", "Tomatoes and basil", "Borrow the long ladder"])
        XCTAssertFalse(exists(file), "the file is set aside once its buds are in")
        XCTAssertTrue(exists(file.deletingLastPathComponent().appendingPathComponent("buds.imported.json")))
    }

    func testTheOldBudsComeInOnlyOnce() async throws {
        let file = try oldFile(kept())
        let vault = MemoryVault(tree: Tree())
        _ = await OldBuds.bring(from: file, platform: .macOS, plant: planting(into: vault))
        let again = await OldBuds.bring(from: file, platform: .macOS, plant: planting(into: vault))
        XCTAssertFalse(again)
        let records = try await vault.snapshot()
        XCTAssertEqual(records.filter { $0.title == "Order seed packets" }.count, 1)
    }

    func testTheFileStaysWhenItsBudsDidNotPlant() async throws {
        let file = try oldFile(kept())
        struct Refused: Error {}
        let planted = await OldBuds.bring(from: file, platform: .iOS) { _ in throw Refused() }
        XCTAssertFalse(planted)
        XCTAssertTrue(exists(file), "the next launch tries again")
        XCTAssertFalse(exists(file.deletingLastPathComponent().appendingPathComponent("buds.imported.json")))
    }

    func testTheUntouchedSampleIsSetAsideUnplanted() async throws {
        let file = try oldFile(Tree.seed())
        let vault = MemoryVault(tree: Tree())
        _ = try await vault.create(parent: nil, title: "Water the ferns", kind: .todo, source: "mac", preferredPath: nil)
        let planted = await OldBuds.bring(from: file, platform: .iOS, plant: planting(into: vault))
        XCTAssertFalse(planted)
        let titles = try await titles(vault)
        XCTAssertEqual(titles, ["Water the ferns"])
        XCTAssertFalse(exists(file))
    }

    func testATouchedSampleIsThePersonsOwn() async throws {
        var sample = Tree.seed()
        let first = try XCTUnwrap(sample.children(of: rootID).first)
        sample.setPinned(first.id, !first.pinned)
        let file = try oldFile(sample)
        let vault = MemoryVault(tree: Tree())
        let planted = await OldBuds.bring(from: file, platform: .iOS, plant: planting(into: vault))
        XCTAssertTrue(planted)
        let titles = try await titles(vault)
        XCTAssertTrue(titles.contains("Launch the newsletter"))
    }

    func testTheTVLeavesTheFileAlone() async throws {
        let file = try oldFile(kept())
        let vault = MemoryVault(tree: Tree())
        let planted = await OldBuds.bring(from: file, platform: .tvOS, plant: planting(into: vault))
        XCTAssertFalse(planted)
        let titles = try await titles(vault)
        XCTAssertTrue(titles.isEmpty)
        XCTAssertTrue(exists(file))
    }

    func testAFileSetAsideBeforeIsNotWrittenOver() async throws {
        let file = try oldFile(kept())
        let earlier = file.deletingLastPathComponent().appendingPathComponent("buds.imported.json")
        try Data("earlier".utf8).write(to: earlier)
        let planted = await OldBuds.bring(from: file, platform: .iOS, plant: planting(into: MemoryVault(tree: Tree())))
        XCTAssertTrue(planted)
        XCTAssertEqual(try Data(contentsOf: earlier), Data("earlier".utf8))
        XCTAssertTrue(exists(file.deletingLastPathComponent().appendingPathComponent("buds.imported 2.json")))
    }
}
