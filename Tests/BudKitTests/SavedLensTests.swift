import XCTest
@testable import BudKit

/// A saved lens as the vault keeps it: a name and a question, read back the same on any device.
final class SavedLensTests: XCTestCase {
    func testAQuestionReadsBackAsItWasAsked() throws {
        let linked = UUID()
        let queries: [LensQuery] = [
            LensQuery(),
            .todos,
            .today,
            .pinnedBuds,
            LensQuery(kind: .note, state: .done, day: .overdue, pinned: true, holdsOpen: true,
                      tags: ["Home/Kitchen", "work"], linked: [linked], grown: true, source: "Mail:1234"),
            LensQuery.todos.and(LensQuery(state: .done)),
        ]
        for query in queries {
            let data = try JSONEncoder().encode(query)
            XCTAssertEqual(try JSONDecoder().decode(LensQuery.self, from: data), query)
        }
        XCTAssertTrue(queries.last!.never, "Open and done at once is kept as nothing answers")
    }

    func testOnlyTheFacetsSetAreWrittenUnderStableKeys() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        func text(_ query: LensQuery) throws -> String { String(decoding: try encoder.encode(query), as: UTF8.self) }
        XCTAssertEqual(try text(LensQuery()), "{}")
        XCTAssertEqual(try text(.todos), #"{"kind":"todo","state":"open"}"#)
        XCTAssertEqual(try text(LensQuery(pinned: true, tags: ["work", "Home"], source: "mail")),
                       #"{"pinned":true,"source":"mail","tags":["home","work"]}"#)
    }

    func testTheMapIsReadSortedByNameAndABadEntryIsSkipped() {
        let a = SavedLens(name: "kitchen", query: LensQuery(tags: ["home"]))
        let b = SavedLens(name: "Errands", query: .todos)
        let stored = [
            a.id.uuidString: a.text!,
            b.id.uuidString: b.text!,
            "not-an-id": b.text!,
            UUID().uuidString: "not json",
            UUID().uuidString: #"{"name":"  ","query":{}}"#,
        ]
        XCTAssertEqual(SavedLens.read(stored), [b, a])
    }

    func testANameIsTrimmedAndAnEmptyOneRefused() {
        XCTAssertEqual(SavedLens.clean("  Morning review \n"), "Morning review")
        XCTAssertNil(SavedLens.clean("   "))
    }

    /// The rows a saved lens ticks ask the question it was saved from.
    func testTheTickedRowsComeBackFromTheQuestionTheyAsked() {
        let linked = UUID()
        let rows: [[LensFacet]] = [
            [.openTodos],
            [.done],
            [.dueToday, .pinned, .recentlyGrown],
            [.openTodos, .tag("home"), .source("mail"), .linked(linked, title: "Pick a name")],
        ]
        for ticked in rows {
            let query = LensFacet.query(of: ticked)!
            let back = LensFacet.facets(of: query) { _ in "Pick a name" }
            XCTAssertEqual(Set(back), Set(ticked))
            XCTAssertEqual(LensFacet.query(of: back), query)
        }
    }

    func testAPageGroupsTheHitsByThread() {
        var tree = Tree()
        let launch = tree.add("Launch the newsletter", todo: false, under: rootID)
        let quiet = tree.add("Quiet thread", todo: false, under: rootID)
        let inner = tree.add("Pick a name", todo: false, under: launch.id)
        let deep = tree.add("Ask the printer", todo: true, under: inner.id)
        _ = tree.add("A note", todo: false, under: quiet.id)
        let open = tree.add("Open the doors", todo: true, under: rootID)
        let groups = LensQuery.todos.hitsByThread(tree)
        XCTAssertEqual(groups.map(\.thread.id), [launch.id, open.id])
        XCTAssertEqual(groups.map { $0.hits.map(\.id) }, [[deep.id], [open.id]])
    }
}
