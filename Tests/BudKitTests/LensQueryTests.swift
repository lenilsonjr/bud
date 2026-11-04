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

    func testTheCanvasPresetsHaveDistinctNamesAndQuestions() {
        let presets = LensQuery.canvasPresets
        XCTAssertEqual(Set(presets.map(\.name)).count, presets.count)
        XCTAssertEqual(Set(presets.map(\.query)).count, presets.count)
        XCTAssertFalse(presets.contains { $0.query.isEmpty })
    }
}
