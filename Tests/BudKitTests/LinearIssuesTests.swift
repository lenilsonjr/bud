import XCTest
@testable import BudKit

final class LinearIssuesTests: XCTestCase {
    private func issue(_ id: String, _ title: String, due: String? = nil, priority: Int = 0, state: String = "started", updated: String = "2026-11-05T10:00:00.000Z") -> String {
        let dueText = due.map { "\"\($0)\"" } ?? "null"
        return """
        {"identifier": "\(id)", "title": "\(title)", "dueDate": \(dueText), "priority": \(priority), "url": "https://linear.app/acme/issue/\(id)", \
        "updatedAt": "\(updated)", "team": {"key": "\(id.split(separator: "-")[0])"}, "state": {"name": "In Progress", "type": "\(state)"}}
        """
    }

    private func window(_ issues: String...) -> String {
        "{\"data\": {\"viewer\": {\"assignedIssues\": {\"nodes\": [\(issues.joined(separator: ","))]}}}}"
    }

    func testTheWindowReadsOpenIssuesAssignedToYouWithTheKeyAsItIs() async throws {
        let http = ScriptedHTTP([(window(
            issue("ENG-12", "Ship the soil", due: "2026-11-10", priority: 2, updated: "2026-11-05T10:00:00.000Z"),
            issue("OPS-3", "Rotate keys", updated: "2026-11-05T11:30:00.000Z")
        ), 200)])
        let result = try await LinearIssues(token: "lin_api_x", http: http).window()
        XCTAssertEqual(http.asked.first?.value(forHTTPHeaderField: "Authorization"), "lin_api_x")
        let query = http.body(0)["query"] as? String ?? ""
        XCTAssertTrue(query.contains("assignedIssues"))
        XCTAssertTrue(query.contains("nin: [\"completed\", \"canceled\"]"))
        XCTAssertEqual(result.items.map(\.id), ["ENG-12", "OPS-3"])
        let first = result.items[0]
        XCTAssertEqual(first.title, "Ship the soil")
        XCTAssertEqual(first.detail, "ENG · In Progress")
        XCTAssertEqual(first.priority, 2)
        XCTAssertTrue(first.todo)
        XCTAssertEqual(first.date, LinearIssues.day("2026-11-10"))
        XCTAssertNil(result.items[1].priority, "Linear's 0 is no priority")
        XCTAssertEqual(result.updated, LinearIssues.instant("2026-11-05T11:30:00.000Z"))
    }

    func testChangesAreAskedForByUpdatedAtSinceTheLastRead() async throws {
        let http = ScriptedHTTP([
            ("{\"data\": {\"viewer\": {\"assignedIssues\": {\"nodes\": []}}}}", 200),
            ("{\"data\": {\"viewer\": {\"assignedIssues\": {\"nodes\": [{\"id\": \"u1\"}]}}}}", 200),
        ])
        let linear = LinearIssues(token: "k", http: http)
        let since = LinearIssues.instant("2026-11-05T11:30:00.000Z")!
        let quiet = try await linear.changed(since: since)
        XCTAssertFalse(quiet)
        let moved = try await linear.changed(since: since)
        XCTAssertTrue(moved)
        let query = http.body(0)["query"] as? String ?? ""
        XCTAssertTrue(query.contains("updatedAt: { gt: \"2026-11-05T11:30:00.000Z\" }"), query)
    }

    func testIssuesAreLookedUpByTeamAndNumberAndMissingOnesSaySo() async throws {
        let http = ScriptedHTTP([("{\"data\": {\"issues\": {\"nodes\": [\(issue("ENG-12", "Ship the soil", state: "completed"))]}}}", 200)])
        let answer = try await LinearIssues(token: "k", http: http).issues(["ENG-12", "ENG-99"])
        XCTAssertEqual(answer.found.map(\.id), ["ENG-12"])
        XCTAssertFalse(answer.found[0].todo, "a completed issue is done")
        XCTAssertEqual(answer.missing, ["ENG-99"])
        let query = http.body(0)["query"] as? String ?? ""
        XCTAssertTrue(query.contains("{ team: { key: { eq: \"ENG\" } }, number: { eq: 99 } }"), query)
    }

    func testACancelledIssueIsDoneAndCancelled() {
        let json = try! JSONSerialization.jsonObject(with: Data(issue("ENG-4", "Old idea", state: "canceled").utf8)) as! [String: Any]
        let item = LinearIssues.item(json)
        XCTAssertEqual(item?.todo, false)
        XCTAssertEqual(item?.cancelled, true)
    }

    func testARefusedKeySaysSoFromTheStatusOrTheErrors() async {
        for reply in [("", 401), ("{\"errors\": [{\"message\": \"no\", \"extensions\": {\"code\": \"AUTHENTICATION_ERROR\"}}]}", 400)] {
            do {
                _ = try await LinearIssues(token: "bad", http: ScriptedHTTP([reply])).workspace()
                XCTFail("Expected a refusal")
            } catch {
                XCTAssertEqual(error as? SourceError, .unauthorized)
            }
        }
    }

    func testAnIdentifierSplitsIntoTeamAndNumber() {
        XCTAssertEqual(LinearIssues.split("ENG-12")?.team, "ENG")
        XCTAssertEqual(LinearIssues.split("ENG-12")?.number, 12)
        XCTAssertNil(LinearIssues.split("nonsense"))
        XCTAssertNil(LinearIssues.split("A\"B-1"), "nothing that could break out of the query")
    }
}

@MainActor
final class LinearSourceTests: XCTestCase {
    private let empty = "{\"data\": {\"viewer\": {\"assignedIssues\": {\"nodes\": []}}}}"
    private func window(_ title: String) -> String {
        """
        {"data": {"viewer": {"assignedIssues": {"nodes": [{"identifier": "ENG-1", "title": "\(title)", "dueDate": null, "priority": 3, \
        "url": "https://linear.app/acme/issue/ENG-1", "updatedAt": "2026-11-05T10:00:00.000Z", "team": {"key": "ENG"}, \
        "state": {"name": "Todo", "type": "unstarted"}}]}}}}
        """
    }

    func testAnAccountIsReadAgainOnlyWhenSomethingWasUpdatedOrAnHourPasses() async {
        let http = ScriptedHTTP([
            (window("Ship"), 200),
            (empty, 200),
            ("{\"data\": {\"viewer\": {\"assignedIssues\": {\"nodes\": [{\"id\": \"u\"}]}}}}", 200), (window("Ship it"), 200),
            (window("Ship it now"), 200),
        ])
        let store = SourceStore(defaults: UserDefaults(suiteName: "lin-\(UUID().uuidString)")!, tokens: MemoryTokens(), http: http)
        var now = Date(timeIntervalSince1970: 1_793_900_000)
        store.clock = { now }
        await store.connectLinear(name: "", token: "k")
        XCTAssertEqual(store.accounts.first?.name, "Linear")
        XCTAssertEqual(store.accounts.first?.items.map(\.title), ["Ship"])
        await store.refresh()
        XCTAssertEqual(http.asked.count, 2, "nothing updated: no window")
        await store.refresh()
        XCTAssertEqual(store.accounts.first?.items.map(\.title), ["Ship it"])
        now += 3601
        await store.refresh()
        XCTAssertEqual(http.asked.count, 5, "an hour on: the window is read without asking")
        XCTAssertEqual(store.accounts.first?.items.map(\.title), ["Ship it now"])
    }

    func testAClosedIssueOutsideTheWindowIsLookedUpAndADeletedOneIsGone() async {
        let closed = """
        {"data": {"issues": {"nodes": [{"identifier": "ENG-7", "title": "Done thing", "dueDate": null, "priority": 0, "url": null, \
        "updatedAt": "2026-11-05T10:00:00.000Z", "team": {"key": "ENG"}, "state": {"name": "Done", "type": "completed"}}]}}}
        """
        let http = ScriptedHTTP([(window("Ship"), 200), (closed, 200)])
        let store = SourceStore(defaults: UserDefaults(suiteName: "lin-\(UUID().uuidString)")!, tokens: MemoryTokens(), http: http)
        await store.connectLinear(name: "Work", token: "k")
        let found = await store.sightings(for: [("linear:ENG-1", nil), ("linear:ENG-7", nil), ("linear:ENG-8", nil)])
        guard case .seen(let open) = found["linear:ENG-1"], case .seen(let done) = found["linear:ENG-7"] else {
            return XCTFail("Expected both seen: \(found)")
        }
        XCTAssertTrue(open.todo)
        XCTAssertFalse(done.todo)
        XCTAssertEqual(found["linear:ENG-8"], .gone)
    }
}

final class LinearLiveRulesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var stamp: String { ISO8601DateFormatter().string(from: now) }
    private let bud = Bud(text: "Ship", state: .open, from: "linear:ENG-1")
    private func issue(due: Date? = nil, todo: Bool = true, cancelled: Bool = false) -> SourceItem {
        SourceItem(id: "ENG-1", title: "Ship", detail: "ENG · Todo", date: due, priority: 2, todo: todo, cancelled: cancelled)
    }

    func testAMovedDueDateRewritesDue() {
        let due = Date(timeIntervalSince1970: 1_800_100_000)
        let result = LiveRules.changes(for: bud, kind: .linear, sighting: .seen(issue(due: due)), last: SourceSnapshot(issue()), now: now)
        XCTAssertEqual(result.changes, [.due(due), .mark("moved \(stamp)")])
    }

    func testCompletedTicksTheBudAndReopenedOpensIt() {
        let done = LiveRules.changes(for: bud, kind: .linear, sighting: .seen(issue(todo: false)), last: SourceSnapshot(issue()), now: now)
        XCTAssertEqual(done.changes, [.state(.done), .mark("closed")])
        let back = LiveRules.changes(
            for: Bud(text: "Ship", state: .open, from: "linear:ENG-1", fromState: "closed"), kind: .linear,
            sighting: .seen(issue()), last: done.seen, now: now)
        XCTAssertEqual(back.changes, [.state(.open), .mark("reopened \(stamp)")])
    }

    func testCancelledTicksTheBudAndSaysCancelled() {
        let result = LiveRules.changes(
            for: bud, kind: .linear, sighting: .seen(issue(todo: false, cancelled: true)), last: SourceSnapshot(issue()), now: now)
        XCTAssertEqual(result.changes, [.state(.done), .mark("cancelled")])
    }
}
