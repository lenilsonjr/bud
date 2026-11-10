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

    func testTheMapIsReadSortedByNameAndAKeyThatIsNoIdIsSkipped() {
        let a = SavedLens(name: "kitchen", query: LensQuery(tags: ["home"]))
        let b = SavedLens(name: "Errands", query: .todos)
        let stored = [
            a.id.uuidString: a.text!,
            b.id.uuidString: b.text!,
            "not-an-id": b.text!,
        ]
        XCTAssertEqual(SavedLens.read(stored), [b, a])
    }

    /// An entry this build cannot make sense of still shows, untitled and matching nothing, so
    /// it can be deleted; renamed, it keeps what it held.
    func testAnUnreadableOrNamelessEntryShowsAsAnUntitledLens() throws {
        let garbled = UUID(), blank = UUID(), noQuery = UUID()
        let read = SavedLens.read([
            garbled.uuidString: "not json",
            blank.uuidString: #"{"name":"  ","query":{"pinned":true}}"#,
            noQuery.uuidString: #"{"name":"Bare"}"#,
        ])
        let byID = Dictionary(uniqueKeysWithValues: read.map { ($0.id, $0) })
        let g = try XCTUnwrap(byID[garbled])
        XCTAssertEqual(g.name, SavedLens.untitled)
        XCTAssertTrue(g.query.never)
        XCTAssertEqual(g.foreign, #""not json""#)
        var renamed = g
        renamed.name = "Old"
        XCTAssertEqual(renamed.text, #"{"name":"Old","query":"not json"}"#)
        let b = try XCTUnwrap(byID[blank])
        XCTAssertEqual(b.name, SavedLens.untitled)
        XCTAssertEqual(b.query, .pinnedBuds, "A question it can read still asks")
        XCTAssertNil(b.foreign)
        let n = try XCTUnwrap(byID[noQuery])
        XCTAssertEqual(n.name, "Bare")
        XCTAssertTrue(n.query.never)
        XCTAssertEqual(n.foreign, "null")
    }

    /// Every lens read back can be written again: keeping one never meets a lens without text.
    func testEveryLensReadHasTextToWrite() {
        let read = SavedLens.read([
            UUID().uuidString: "not json",
            UUID().uuidString: #"{"name":"New","query":{"mood":"calm"}}"#,
            UUID().uuidString: SavedLens(name: "To-dos", query: .todos).text!,
        ])
        XCTAssertEqual(read.count, 3)
        XCTAssertTrue(read.allSatisfy { $0.text != nil })
    }

    func testTheOfferedNameFollowsTheRowsUntilOneIsTyped() {
        let offered = SavedLens.followRows(name: "Pinned", suggested: "Pinned", rows: ["Pinned", "#home"])
        XCTAssertEqual(offered.name, "Pinned, #home")
        XCTAssertEqual(offered.suggested, "Pinned, #home")
        let typed = SavedLens.followRows(name: "Kitchen", suggested: "Pinned", rows: ["Pinned", "#home"])
        XCTAssertEqual(typed.name, "Kitchen", "Typed text stays")
        XCTAssertEqual(typed.suggested, "Pinned, #home")
    }

    func testANameIsTrimmedAndAnEmptyOneRefused() {
        XCTAssertEqual(SavedLens.clean("  Morning review \n"), "Morning review")
        XCTAssertNil(SavedLens.clean("   "))
    }

    /// A question a newer build wrote, with a key or a value this one does not know, matches
    /// nothing, and a rename here writes the question back as it was.
    func testAQuestionFromANewerBuildMatchesNothingAndARenameKeepsIt() throws {
        let key = UUID(), value = UUID()
        let newer = #"{"name":"Events","query":{"kind":"event","tags":["home/kitchen"]}}"#
        let stored = [
            key.uuidString: #"{"name":"Mood","query":{"mood":"calm","pinned":true}}"#,
            value.uuidString: newer,
        ]
        let read = SavedLens.read(stored)
        XCTAssertEqual(read.map(\.name), ["Events", "Mood"])
        var tree = Tree()
        let pinned = tree.add("Pinned", todo: false, under: rootID)
        tree.setPinned(pinned.id, true)
        for lens in read {
            XCTAssertTrue(lens.query.never)
            XCTAssertNotNil(lens.foreign)
            XCTAssertEqual(lens.query.hits(tree), [])
        }
        var events = read[0]
        events.name = "Renamed"
        XCTAssertEqual(events.text, #"{"name":"Renamed","query":{"kind":"event","tags":["home/kitchen"]}}"#)
        var mood = read[1]
        mood.name = "Calm"
        XCTAssertEqual(mood.text, #"{"name":"Calm","query":{"mood":"calm","pinned":true}}"#)
        XCTAssertEqual(SavedLens.read([key.uuidString: mood.text!]).first?.foreign, mood.foreign, "Read again the same")
    }

    /// A known key in a shape this build does not expect keeps the entry, matching nothing.
    func testAKnownKeyOfAnotherShapeMatchesNothingAndKeepsItsText() throws {
        let source = UUID(), day = UUID(), odd = UUID()
        let read = SavedLens.read([
            source.uuidString: #"{"name":"Sources","query":{"source":["a","b"]}}"#,
            day.uuidString: #"{"name":"Days","query":{"day":{"before":3}}}"#,
            odd.uuidString: #"{"name":"Odd","query":5}"#,
        ])
        XCTAssertEqual(read.map(\.name), ["Days", "Odd", "Sources"])
        XCTAssertTrue(read.allSatisfy { $0.query.never })
        XCTAssertEqual(read.map(\.foreign), [#"{"day":{"before":3}}"#, "5", #"{"source":["a","b"]}"#])
        var days = read[0]
        days.name = "Later"
        XCTAssertEqual(days.text, #"{"name":"Later","query":{"day":{"before":3}}}"#)
    }

    func testATagRenameReachesALensThatAsksForItButNotAForeignOne() throws {
        let lens = SavedLens(name: "Kitchen", query: LensQuery(pinned: true, tags: ["home/kitchen", "work"]))
        let renamed = try XCTUnwrap(lens.renamingTag("Home", to: "house"))
        XCTAssertEqual(renamed.query.tags, ["house/kitchen", "work"])
        XCTAssertEqual(renamed.id, lens.id)
        XCTAssertTrue(renamed.query.pinned)
        XCTAssertNil(lens.renamingTag("garden", to: "yard"), "Not asked for")
        let foreign = try XCTUnwrap(SavedLens.read([UUID().uuidString: #"{"name":"New","query":{"tags":["home"],"mood":"calm"}}"#]).first)
        XCTAssertNil(foreign.renamingTag("home", to: "house"))
    }

    /// The ticked rows follow the saved lenses: a deleted one drops out, a changed one asks as
    /// it is now.
    func testTheTickedRowsFollowTheSavedLenses() throws {
        let kitchen = SavedLens(name: "Kitchen", query: LensQuery(tags: ["home"]))
        let ticked: [LensFacet] = [.saved(kitchen), .pinned]
        XCTAssertNil(LensFacet.synced(ticked, with: [kitchen]), "Nothing changed")
        XCTAssertEqual(LensFacet.synced(ticked, with: []), [.pinned])
        var renamed = kitchen
        renamed.name = "Cooking"
        renamed.query.tags = ["house"]
        let synced = try XCTUnwrap(LensFacet.synced(ticked, with: [renamed]))
        XCTAssertEqual(synced.first?.name, "Cooking")
        XCTAssertEqual(LensFacet.query(of: synced), LensQuery(pinned: true, tags: ["house"]))
    }

    func testTwoLensesAskTheSameQuestionByQueryOrByForeignText() throws {
        let a = SavedLens(name: "A", query: .todos)
        XCTAssertTrue(a.asksSame(as: SavedLens(name: "B", query: .todos)))
        XCTAssertFalse(a.asksSame(as: SavedLens(name: "A", query: .today)))
        let text = #"{"name":"N","query":{"mood":"calm"}}"#
        let x = try XCTUnwrap(SavedLens.read([UUID().uuidString: text]).first)
        let y = try XCTUnwrap(SavedLens.read([UUID().uuidString: text]).first)
        XCTAssertTrue(x.asksSame(as: y))
        XCTAssertFalse(x.asksSame(as: SavedLens(name: "N", query: x.query)), "A foreign question is its text")
    }

    func testAQuestionThisBuildKnowsCarriesNoForeignText() {
        let lens = SavedLens(name: "To-dos", query: .todos)
        XCTAssertNil(SavedLens.read([lens.id.uuidString: lens.text!]).first?.foreign)
    }

    /// A saved lens on the canvas asks its own question, whatever the menu's rows can say.
    func testASavedLensAsksItsQuestionExactly() {
        let lens = SavedLens(name: "Notes overdue", query: LensQuery(kind: .note, day: .overdue, holdsOpen: true))
        XCTAssertEqual(LensFacet.query(of: [.saved(lens)]), lens.query)
        XCTAssertEqual(LensFacet.saved(lens), LensFacet.saved(SavedLens(id: lens.id, name: "Renamed", query: .todos)), "One row per lens")
    }

    /// A bud the lens is linked with that has gone keeps the lens matching nothing.
    func testALensLinkedWithAGoneBudMatchesNothing() {
        var tree = Tree()
        let thread = tree.add("Thread", todo: false, under: rootID)
        _ = tree.add("Open", todo: true, under: thread.id)
        let lens = SavedLens(name: "Around it", query: LensQuery(kind: .todo, linked: [UUID()]))
        XCTAssertEqual(LensFacet.query(of: [.saved(lens)])?.hits(tree), [])
        XCTAssertEqual(LensQuery(kind: .todo).hits(tree).count, 1, "Broader, it would match")
    }

    func testALensIsRefusedWithoutAQuestionANameOrWhenSavedAlready() {
        let kept = SavedLens(name: "To-dos", query: .todos)
        XCTAssertEqual(SavedLens.refusal(name: "A", query: nil, saved: []), "Tick a row to save a lens")
        XCTAssertEqual(SavedLens.refusal(name: "A", query: LensQuery(), saved: []), "Tick a row to save a lens")
        XCTAssertEqual(SavedLens.refusal(name: "A", query: LensQuery.todos.and(LensQuery(state: .done)), saved: []),
                       "Nothing can match these rows")
        XCTAssertEqual(SavedLens.refusal(name: "A", query: .todos, saved: [kept]), "Saved already as To-dos")
        XCTAssertEqual(SavedLens.refusal(name: "  ", query: .today, saved: [kept]), "Give the lens a name")
        XCTAssertNil(SavedLens.refusal(name: "Today", query: .today, saved: [kept]))
        XCTAssertNil(SavedLens.refusal(query: .today, saved: [kept]), "The button shows before a name")
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
