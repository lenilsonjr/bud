import XCTest
@testable import BudKit

final class LensQueryTests: XCTestCase {
    let day = Date(timeIntervalSince1970: 1_800_000_000)

    func testThePresetsAskWhatTheFilesLensesShow() {
        var t = Tree.seed()
        let thread = t.children(of: rootID)[0]
        let due = t.add("Due today", todo: true, under: thread.id)
        let planned = t.add("Planned note", todo: false, under: thread.id)
        t.setDue(due.id, day)
        t.setWhen(planned.id, day)
        t.setPinned(planned.id, true)

        XCTAssertEqual(Set(LensQuery.todos.hits(t, on: day).map(\.id)),
                       Set(t.openTodos().flatMap(\.todos).map(\.id)))
        XCTAssertEqual(LensQuery.pinnedBuds.hits(t, on: day).map(\.id), t.pinned().map(\.id))
        XCTAssertTrue(t.pinned().contains { $0.id == planned.id })
        let today = t.today(on: day)
        XCTAssertEqual(Set(LensQuery.today.hits(t, on: day).map(\.id)),
                       Set((today.due + today.scheduled).map(\.id)))
    }

    func testHitsLightAndTheirAncestorsAreThePath() {
        var t = Tree()
        let thread = t.add("Thread", todo: false, under: rootID)
        let inner = t.add("Inner", todo: false, under: thread.id)
        let open = t.add("Open", todo: true, under: inner.id)
        let other = t.add("Other", todo: false, under: rootID)
        let closed = t.add("Closed", todo: true, under: other.id)
        t.toggle(closed.id)

        let light = LensQuery.todos.light(t, on: day)
        XCTAssertEqual(light[open.id], .hit)
        XCTAssertEqual(light[inner.id], .path)
        XCTAssertEqual(light[thread.id], .path)
        XCTAssertEqual(light[rootID], .path)
        XCTAssertNil(light[other.id], "No hit below it: a miss")
        XCTAssertNil(light[closed.id], "Done is not open")

        XCTAssertTrue(LensQuery.todos.light(Tree(), on: day).isEmpty, "Nothing hits, nothing lights, not even the root")
    }

    func testFacetsCombineAndHoldsOpenLooksBelow() {
        var t = Tree()
        let thread = t.add("Thread", todo: false, under: rootID)
        let todo = t.add("Pinned to-do", todo: true, under: thread.id)
        let note = t.add("Pinned note", todo: false, under: thread.id)
        _ = t.add("Empty", todo: false, under: rootID)
        t.setPinned(todo.id, true)
        t.setPinned(note.id, true)

        XCTAssertEqual(LensQuery(kind: .todo, pinned: true).hits(t, on: day).map(\.id), [todo.id])
        XCTAssertEqual(LensQuery(kind: .note, pinned: true).hits(t, on: day).map(\.id), [note.id])
        XCTAssertEqual(LensQuery(holdsOpen: true).hits(t, on: day).map(\.id), [thread.id])
        t.toggle(todo.id)
        XCTAssertTrue(LensQuery(holdsOpen: true).hits(t, on: day).isEmpty, "Closed below: holds nothing open")
        XCTAssertEqual(LensQuery(kind: .todo, state: .done).hits(t, on: day).map(\.id), [todo.id])
        XCTAssertTrue(LensQuery().isEmpty)
        XCTAssertEqual(LensQuery().hits(t, on: day).count, 4, "No facets: every bud")
    }

    func testOverdueIsOpenAndDueBeforeTheDay() {
        var t = Tree()
        let late = t.add("Late", todo: true, under: rootID)
        let now = t.add("Now", todo: true, under: rootID)
        let lateDone = t.add("Late but done", todo: true, under: rootID)
        t.setDue(late.id, day.addingTimeInterval(-86_400 * 2))
        t.setDue(now.id, day)
        t.setDue(lateDone.id, day.addingTimeInterval(-86_400 * 2))
        t.toggle(lateDone.id)
        XCTAssertEqual(LensQuery(day: .overdue).hits(t, on: day).map(\.id), [late.id])
    }

    func testInboxCapturesAreNeverHits() {
        var t = Tree()
        let captured = t.capture("Call back", source: "mac")
        XCTAssertFalse(LensQuery().hits(t, on: day).contains { $0.id == captured.id })
    }

    func testUnderALensHitsAreFullPathsHalfAndTheRestFadeBelowAnyDim() {
        XCTAssertEqual(lensLevel(0.35, match: nil, lensOn: false), 0.35, "No lens: as before")
        XCTAssertEqual(lensLevel(0.35, match: .hit, lensOn: true), 1)
        XCTAssertEqual(lensLevel(1, match: .path, lensOn: true), 0.55)
        XCTAssertLessThan(lensLevel(1, match: nil, lensOn: true), lightLevel(role: .deep, lifted: false))
    }

    func testTheBuiltInLensRowsHaveDistinctNamesAndQuestions() {
        let rows = LensFacet.builtIns
        XCTAssertEqual(Set(rows.map(\.name)).count, rows.count)
        XCTAssertEqual(Set(rows.map(\.query)).count, rows.count)
        XCTAssertFalse(rows.contains { $0.query.isEmpty })
    }

    func testVoiceOverHearsWhereACardStandsUnderALens() {
        XCTAssertEqual(spokenValue(done: false, match: nil, lensOn: false), "")
        XCTAssertEqual(spokenValue(done: true, match: nil, lensOn: false), "Done")
        XCTAssertEqual(spokenValue(done: false, match: .hit, lensOn: true), "Matches")
        XCTAssertEqual(spokenValue(done: true, match: .path, lensOn: true), "Done, Holds a match")
        XCTAssertEqual(spokenValue(done: false, match: nil, lensOn: true), "No match")
    }

    func testALensThatFindsNothingLightsNothing() {
        var t = Tree()
        _ = t.add("A note", todo: false, under: rootID)
        XCTAssertTrue(LensQuery(day: .overdue).light(t, on: day).isEmpty)
    }

    func testATagFacetMatchesListAndBodyTagsInAnyCaseAndNestedOnes() {
        let a = Bud(text: "A", tags: ["Home"])
        let b = Bud(text: "B", body: "#home/kitchen #errands")
        let c = Bud(text: "C", body: "#homework")
        let tree = Tree(buds: [a, b, c])
        XCTAssertEqual(Set(LensQuery(tags: ["HOME"]).hits(tree).map(\.id)), [a.id, b.id])
        XCTAssertEqual(LensQuery(tags: ["home", "errands"]).hits(tree).map(\.id), [b.id], "every tag must hold")
        XCTAssertEqual(LensQuery(state: .open, tags: ["home"]).hits(tree).map(\.id), [])
    }

    func testTickedFacetsCombineAndAContradictionMatchesNothing() {
        let open = Bud(text: "Open", state: .open, tags: ["home"])
        let done = Bud(text: "Done", state: .done, tags: ["home"])
        let note = Bud(text: "Note", tags: ["work"])
        let tree = Tree(buds: [open, done, note])
        XCTAssertNil(LensFacet.query(of: []))
        XCTAssertEqual(LensFacet.query(of: [.openTodos, .tag("home")])?.hits(tree).map(\.id), [open.id])
        XCTAssertEqual(Set(LensFacet.query(of: [.tag("home")])?.hits(tree).map(\.id) ?? []), [open.id, done.id])
        XCTAssertEqual(LensFacet.query(of: [.openTodos, .done])?.hits(tree).map(\.id), [], "open and done at once")
        XCTAssertEqual(LensFacet.query(of: [.tag("home"), .tag("work")])?.hits(tree).map(\.id), [])
    }

    func testATickedTagStaysTickedWhenTheMenuSpellsItAnotherWay() {
        XCTAssertEqual(LensFacet.tag("home"), .tag("Home"))
        XCTAssertEqual(Set<LensFacet>([.tag("home"), .tag("HOME")]).count, 1)
        XCTAssertNotEqual(LensFacet.tag("home"), .tag("home/garden"))
        XCTAssertTrue([LensFacet.tag("home")].contains(.tag("Home")))
    }

    func testALinkedFacetMatchesBudsLinkedEitherWay() {
        var t = Tree()
        let plan = t.add("Plan", todo: false, under: rootID)
        let out = t.add("Out", todo: false, under: rootID)
        let into = t.add("Into", todo: true, under: rootID)
        let alone = t.add("Alone", todo: false, under: rootID)
        t.setBody(plan.id, "See [[Out]]")
        t.setBody(into.id, "For the [[Plan]]")
        t.setBody(alone.id, "Nothing here")

        let facet = LensFacet.linked(plan.id, title: "Plan")
        XCTAssertEqual(facet.name, "Linked to Plan")
        XCTAssertEqual(Set(facet.query.hits(t).map(\.id)), [out.id, into.id])
        XCTAssertEqual(LensFacet.query(of: [facet, .openTodos])?.hits(t).map(\.id), [into.id])
        XCTAssertEqual(LensFacet.linked(plan.id, title: "Old name"), facet, "one bud is one row")
        XCTAssertEqual(LensFacet.query(of: [facet, .linked(out.id, title: "Out")])?.hits(t).map(\.id), [],
                       "nothing is linked with both")
        XCTAssertEqual(LensFacet.linked(alone.id, title: "Alone").query.hits(t).map(\.id), [])
        let light = facet.query.light(t, links: LinkGraph(t))
        XCTAssertEqual(light[out.id], .hit)
        XCTAssertEqual(light[plan.id], .path, "the bud asked about stays in view")
        XCTAssertNil(light[alone.id])
        XCTAssertTrue(LensFacet.linked(alone.id, title: "Alone").query.light(t).isEmpty, "nothing hits, nothing lit")
    }

    func testRecentlyGrownMatchesWhatGainedABudThisWeek() {
        var t = Tree()
        let fresh = t.add("Fresh", todo: false, under: rootID)
        let inner = t.add("Inner", todo: false, under: fresh.id)
        let stale = t.add("Stale", todo: false, under: rootID)
        let six = t.add("Six days old", todo: true, under: inner.id)
        let eight = t.add("Eight days old", todo: false, under: stale.id)
        for i in t.buds.indices { t.buds[i].created = day.addingTimeInterval(-30 * 86_400) }
        func age(_ id: UUID, days: Double) {
            if let i = t.buds.firstIndex(where: { $0.id == id }) { t.buds[i].created = day.addingTimeInterval(-days * 86_400) }
        }
        age(six.id, days: 6)
        age(eight.id, days: 8)

        let grown = LensFacet.recentlyGrown.query.hits(t, on: day).map(\.id)
        XCTAssertEqual(Set(grown), [fresh.id, inner.id], "what holds the six-day-old bud, at any depth")
        XCTAssertEqual(LensFacet.query(of: [.recentlyGrown, .openTodos])?.hits(t, on: day).map(\.id), [],
                       "the holders are notes")
        XCTAssertEqual(LensFacet.recentlyGrown.query.light(t, on: day)[rootID], .path)
    }

    func testASourceFacetMatchesBudsByTheSourceBeforeTheColon() {
        var t = Tree()
        let issue = t.add("Ship the fix", todo: true, under: rootID)
        let pr = t.add("Review the PR", todo: true, under: rootID)
        let note = t.add("Typed here", todo: false, under: rootID)
        let mac = t.add("Captured on the Mac", todo: false, under: rootID)
        for (id, source) in [(issue.id, "mail:1234"), (pr.id, "Web:page-12"), (mac.id, "mac")] {
            if let i = t.buds.firstIndex(where: { $0.id == id }) { t.buds[i].source = source }
        }

        XCTAssertEqual(LensFacet.source("mail").query.hits(t).map(\.id), [issue.id])
        XCTAssertEqual(LensFacet.source("web").query.hits(t).map(\.id), [pr.id])
        XCTAssertEqual(LensFacet.source("mac").query.hits(t).map(\.id), [mac.id])
        XCTAssertFalse(LensFacet.source("mail").query.hits(t).contains { $0.id == note.id })
        XCTAssertEqual(LensFacet.source("web").name, "From Web")
        XCTAssertEqual(LensFacet.query(of: [.source("mail"), .openTodos])?.hits(t).map(\.id), [issue.id])
        XCTAssertEqual(LensFacet.query(of: [.source("mail"), .source("web")])?.hits(t).map(\.id), [],
                       "one bud has one source")
        XCTAssertEqual(LensQuery.sourceKey(" Mail :x"), "mail")
        XCTAssertNil(LensQuery.sourceKey(":x"))
        XCTAssertEqual(LensQuery.sourceKey("desktop"), "mac", "the Mac's capture panel")
    }
}
