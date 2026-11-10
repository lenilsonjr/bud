import XCTest
@testable import BudKit

final class VaultTests: XCTestCase {
    private func vault() -> MemoryVault { MemoryVault(tree: Tree.seed()) }

    private func path(of title: String, in records: [BudRecord]) throws -> String {
        try XCTUnwrap(records.first { $0.title == title }, "No bud titled \(title)").path
    }

    func testRecordsRoundTripTheSeedWorld() {
        let seed = Tree.seed()
        let back = Tree(records: seed.records())
        XCTAssertEqual(Set(back.buds.map(\.id)), Set(seed.buds.map(\.id)))
        for bud in seed.buds {
            let other = back.bud(bud.id)
            XCTAssertEqual(other?.text, bud.text)
            XCTAssertEqual(other?.parent, bud.parent)
            XCTAssertEqual(other?.state, bud.state)
            XCTAssertEqual(other?.due, bud.due)
            XCTAssertEqual(other?.when, bud.when)
            XCTAssertEqual(other?.pinned, bud.pinned)
            XCTAssertEqual(other?.source, bud.source)
            XCTAssertEqual(other?.body, bud.body)
        }
        XCTAssertEqual(back.records(), Tree(records: back.records()).records(), "A second trip changes nothing")
    }

    func testRecordsCarryPlaceKindAndParent() async throws {
        let records = try await vault().snapshot()
        let thread = try XCTUnwrap(records.first { $0.title == "Launch the newsletter" })
        XCTAssertEqual(thread.kind, .todo)
        XCTAssertNil(thread.parent)
        XCTAssertEqual(thread.place, .everything)
        XCTAssertTrue(thread.pinned)
        let name = try XCTUnwrap(records.first { $0.title == "Pick a name" })
        XCTAssertEqual(name.parent, thread.path)
        XCTAssertNotNil(name.due)
        let capture = try XCTUnwrap(records.first { $0.title == "Ask the printer about paper samples" })
        XCTAssertEqual(capture.place, .inbox)
        XCTAssertEqual(capture.source, "mac")
        let note = try XCTUnwrap(records.first { $0.title == "Routines" })
        XCTAssertEqual(note.kind, .note)
        XCTAssertNil(note.state)
    }

    func testParentsComeBeforeChildren() async throws {
        let records = try await vault().snapshot()
        var seen: Set<String> = []
        for record in records {
            if let parent = record.parent, parent != inboxID.uuidString {
                XCTAssertTrue(seen.contains(parent), "\(record.title) came before its parent")
            }
            seen.insert(record.path)
        }
    }

    func testCreateEditTickMoveTrashAndRestore() async throws {
        let vault = vault()
        var records = try await vault.snapshot()
        let thread = try path(of: "Launch the newsletter", in: records)
        let other = try path(of: "Q4 roadmap", in: records)

        let made = try await vault.create(parent: thread, title: "Book the printer", kind: .todo, source: nil, preferredPath: nil)
        records = try await vault.snapshot()
        let created = try XCTUnwrap(records.first { $0.path == made })
        XCTAssertEqual(created.parent, thread)
        XCTAssertEqual(created.state, .open)

        _ = try await vault.rename(made, to: "Book the printer early")
        try await vault.setBody(made, "Ask about paper weights.")
        try await vault.setPinned(made, true)
        try await vault.setState(made, .done)
        records = try await vault.snapshot()
        let edited = try XCTUnwrap(records.first { $0.path == made })
        XCTAssertEqual(edited.title, "Book the printer early")
        XCTAssertEqual(edited.body, "Ask about paper weights.")
        XCTAssertTrue(edited.pinned)
        XCTAssertEqual(edited.state, .done)

        try await vault.setState(made, nil)
        let note = try await vault.snapshot().first { $0.path == made }
        XCTAssertEqual(note?.kind, .note)

        _ = try await vault.move(made, to: other)
        records = try await vault.snapshot()
        XCTAssertEqual(records.first { $0.path == made }?.parent, other)

        try await vault.trash(made)
        records = try await vault.snapshot()
        XCTAssertEqual(records.first { $0.path == made }?.place, .trash)
        let restored = try await vault.restore(made)
        XCTAssertEqual(restored, made)
        records = try await vault.snapshot()
        XCTAssertEqual(records.first { $0.path == made }?.place, .everything)
        XCTAssertEqual(records.first { $0.path == made }?.parent, other)
    }

    func testTrashTakesTheBranchAndRestoreBringsItBack() async throws {
        let vault = vault()
        let before = try await vault.snapshot()
        let thread = try path(of: "Launch the newsletter", in: before)
        try await vault.trash(thread)
        let during = try await vault.snapshot()
        XCTAssertEqual(during.count, before.count)
        XCTAssertEqual(during.filter { $0.place == .trash }.count, 12)
        _ = try await vault.restore(thread)
        let after = try await vault.snapshot()
        XCTAssertEqual(Set(after), Set(before))
        XCTAssertEqual(after.map(\.path), before.map(\.path), "Same reading order")
    }

    func testDeleteForeverAndEmptyTrash() async throws {
        let vault = vault()
        let records = try await vault.snapshot()
        let roadmap = try path(of: "Q4 roadmap", in: records)
        let language = try path(of: "Learn a language", in: records)
        try await vault.trash(roadmap)
        try await vault.trash(language)
        try await vault.deleteForever(roadmap)
        var now = try await vault.snapshot()
        XCTAssertNil(now.first { $0.title == "Q4 roadmap" })
        XCTAssertEqual(now.first { $0.title == "Learn a language" }?.place, .trash)
        try await vault.emptyTrash()
        now = try await vault.snapshot()
        XCTAssertEqual(now.filter { $0.place == .trash }.count, 0)
    }

    func testAMoveUnderItsOwnBranchIsRefused() async throws {
        let vault = vault()
        let records = try await vault.snapshot()
        let thread = try path(of: "Launch the newsletter", in: records)
        let name = try path(of: "Pick a name", in: records)
        do {
            _ = try await vault.move(thread, to: name)
            XCTFail("Expected a refusal")
        } catch {
            XCTAssertEqual(error as? VaultError, .refused("Cannot move \(thread) there"))
        }
    }

    func testAnUnknownPathIsNotFound() async {
        let vault = vault()
        do {
            try await vault.setBody(UUID().uuidString, "x")
            XCTFail("Expected not found")
        } catch {
            XCTAssertTrue(error is VaultError)
        }
    }

    func testQueriesAnswerFromTheTree() async throws {
        let vault = vault()
        let records = try await vault.snapshot()
        let name = try path(of: "Pick a name", in: records)
        let thread = try path(of: "Launch the newsletter", in: records)

        let counts = try await vault.counts(name)
        XCTAssertEqual(counts, CountsRecord(inside: 3, openTodos: 2))

        let hits = try await vault.search("sender", limit: 10)
        XCTAssertEqual(hits.map(\.title), ["Set up the sender"])
        XCTAssertEqual(hits.first?.trail, ["Everything", "Launch the newsletter"])

        let today = try await vault.today(Date())
        XCTAssertTrue(today.contains { $0.bud.title == "Verify the address" })
        XCTAssertTrue(today.contains { $0.bud.title == "A walk before the first meeting" })

        let next = try await vault.nextStep(under: thread, date: Date())
        XCTAssertEqual(next?.bud.title, "Verify the address")
        let nowhere = try await vault.nextStep(under: try path(of: "Routines", in: records), date: Date())
        XCTAssertNil(nowhere)
    }

    func testWatchHearsExternalChangesUntilCancelled() async throws {
        let vault = vault()
        let heard = Counter()
        let watch = try await vault.watch { heard.bump() }
        await vault.externalChange { $0.add("Added in the folder", todo: false, under: rootID) }
        XCTAssertEqual(heard.value, 1)
        let records = try await vault.snapshot()
        XCTAssertNotNil(records.first { $0.title == "Added in the folder" })
        watch.cancel()
        try await Task.sleep(for: .milliseconds(100))
        await vault.externalChange { $0.add("Added again", todo: false, under: rootID) }
        XCTAssertEqual(heard.value, 1)
    }

    func testAFileVaultWritesAfterEveryChangeAndReadsItBack() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let vault = MemoryVault(tree: Tree.seed(), fileURL: url)
        let made = try await vault.create(parent: nil, title: "Plan the spring issue", kind: .note, source: nil, preferredPath: nil)
        let data = try Data(contentsOf: url)
        let tree = try JSONDecoder().decode(Tree.self, from: data)
        XCTAssertEqual(tree.bud(Bud.id(forPath: made))?.text, "Plan the spring issue")
    }

    func testPathsThatAreNotIdsStillMapToOneStableBud() {
        XCTAssertEqual(Bud.id(forPath: "launch/pick-a-name.md"), Bud.id(forPath: "launch/pick-a-name.md"))
        XCTAssertNotEqual(Bud.id(forPath: "launch/pick-a-name.md"), Bud.id(forPath: "launch/set-up-the-sender.md"))
        let id = UUID()
        XCTAssertEqual(Bud.id(forPath: id.uuidString), id)
    }

    func testPlantingAnItemTwiceFindsTheBudItMade() async throws {
        let vault = vault()
        let first = try await vault.plant(parent: nil, title: "Lease draft", kind: .note, from: "mail:M-1", preferredPath: nil)
        XCTAssertTrue(first.new)
        let record = try await vault.snapshot().first { $0.path == first.path }
        XCTAssertEqual(record?.from, "mail:M-1")
        XCTAssertEqual(record?.title, "Lease draft")

        let again = try await vault.plant(parent: vault.inboxPath, title: "Lease draft", kind: .note, from: "mail:M-1", preferredPath: nil)
        XCTAssertEqual(again, Planting(path: first.path, new: false))

        try await vault.trash(first.path)
        let after = try await vault.plant(parent: nil, title: "Lease draft", kind: .note, from: "mail:M-1", preferredPath: nil)
        XCTAssertTrue(after.new, "a bud in the Trash is planted again")
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func bump() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
