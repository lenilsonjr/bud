import XCTest
@testable import BudKit

final class GitHubItemsTests: XCTestCase {
    private func issue(
        _ repo: String, _ number: Int, _ title: String, pull: Bool = false, state: String = "open", merged: Bool = false,
        reason: String? = nil, updated: String = "2026-11-05T10:00:00Z"
    ) -> String {
        let kind = pull ? "pull" : "issues"
        var fields = [
            "\"number\": \(number)", "\"title\": \"\(title)\"", "\"state\": \"\(state)\"",
            "\"html_url\": \"https://github.com/\(repo)/\(kind)/\(number)\"", "\"updated_at\": \"\(updated)\"",
            "\"repository_url\": \"https://api.github.com/repos/\(repo)\"",
        ]
        if pull { fields.append("\"pull_request\": {\"merged_at\": \(merged ? "\"2026-11-06T10:00:00Z\"" : "null")}") }
        if let reason { fields.append("\"state_reason\": \"\(reason)\"") }
        return "{\(fields.joined(separator: ", "))}"
    }

    private func found(_ issues: String...) -> String {
        "{\"total_count\": \(issues.count), \"incomplete_results\": false, \"items\": [\(issues.joined(separator: ","))]}"
    }

    func testTheUserIsAskedWithTheTokenAndGitHubsHeaders() async throws {
        let http = ScriptedHTTP([("{\"login\": \"octocat\"}", 200)])
        let login = try await GitHubItems(token: "github_pat_x", http: http).user()
        XCTAssertEqual(login, "octocat")
        let request = try XCTUnwrap(http.asked.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/user")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer github_pat_x")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
    }

    func testASearchReadsOpenItemsWithTheirRoleAndHandsBackTheTag() async throws {
        let http = ScriptedHTTP(headed: [(found(issue("octocat/hello-world", 12, "Fix the typo", pull: true)), 200, ["ETag": "W/\"abc\""])])
        let result = try await GitHubItems(token: "t", http: http).search(.reviews)
        let request = try XCTUnwrap(http.asked.first)
        XCTAssertEqual(request.url?.path, "/search/issues")
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
        XCTAssertEqual(query, "is:open is:pr review-requested:@me")
        XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"), "a first read asks without a tag")
        XCTAssertEqual(result.tag, "W/\"abc\"")
        let item = try XCTUnwrap(result.items?.first)
        XCTAssertEqual(item.id, "octocat/hello-world#12")
        XCTAssertEqual(item.title, "Fix the typo")
        XCTAssertEqual(item.detail, "octocat/hello-world · Pull request")
        XCTAssertEqual(item.role, .reviewRequest)
        XCTAssertTrue(item.todo)
        XCTAssertFalse(item.cancelled)
        XCTAssertEqual(item.date, GitHubItems.instant("2026-11-05T10:00:00Z"))
        XCTAssertEqual(item.url?.absoluteString, "https://github.com/octocat/hello-world/pull/12")
    }

    func testTheTagGoesBackAsIfNoneMatchAndNothingChangedKeepsTheItems() async throws {
        let http = ScriptedHTTP(headed: [("", 304, [:])])
        let result = try await GitHubItems(token: "t", http: http).search(.assigned, tag: "W/\"abc\"")
        XCTAssertEqual(http.asked.first?.value(forHTTPHeaderField: "If-None-Match"), "W/\"abc\"")
        XCTAssertNil(result.items, "nothing changed: the last items stand")
        XCTAssertEqual(result.tag, "W/\"abc\"")
    }

    func testIssuesAreLookedUpByRepositoryAndNumberAndMissingOnesSaySo() async throws {
        let http = ScriptedHTTP([
            (issue("octocat/hello-world", 7, "Old thing", pull: true, state: "closed", merged: true), 200),
            ("{\"message\": \"Not Found\"}", 404),
        ])
        let answer = try await GitHubItems(token: "t", http: http).issues(["octocat/hello-world#7", "octocat/hello-world#99", "nonsense"])
        XCTAssertEqual(http.asked.map { $0.url?.path }, ["/repos/octocat/hello-world/issues/7", "/repos/octocat/hello-world/issues/99"])
        XCTAssertEqual(answer.found.map(\.id), ["octocat/hello-world#7"])
        XCTAssertFalse(answer.found[0].todo, "a merged pull request is done")
        XCTAssertFalse(answer.found[0].cancelled)
        XCTAssertEqual(answer.missing, ["octocat/hello-world#99", "nonsense"])
    }

    func testAnIssueThisTokenMayNotReadIsNeitherFoundNorMissing() async throws {
        let http = ScriptedHTTP([("{\"message\": \"Forbidden\"}", 403), ("{\"message\": \"Not Found\"}", 404)])
        let answer = try await GitHubItems(token: "t", http: http).issues(["octocat/private#1", "octocat/hello-world#99"])
        XCTAssertEqual(answer.found, [])
        XCTAssertEqual(answer.missing, ["octocat/hello-world#99"])
    }

    func testClosedWithoutBeingDoneIsCancelled() {
        func item(_ text: String) -> SourceItem? {
            GitHubItems.item(try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any], role: nil)
        }
        let unmerged = item(issue("octocat/hello-world", 3, "Try", pull: true, state: "closed"))
        XCTAssertEqual(unmerged?.todo, false)
        XCTAssertEqual(unmerged?.cancelled, true)
        let notPlanned = item(issue("octocat/hello-world", 4, "Idea", state: "closed", reason: "not_planned"))
        XCTAssertEqual(notPlanned?.cancelled, true)
        let completed = item(issue("octocat/hello-world", 5, "Done", state: "closed", reason: "completed"))
        XCTAssertEqual(completed?.todo, false)
        XCTAssertEqual(completed?.cancelled, false)
        XCTAssertEqual(completed?.detail, "octocat/hello-world · Issue")
    }

    func testAPlantedItemCarriesItsRepositoryAndNumberInTheFromKey() {
        let json = try! JSONSerialization.jsonObject(with: Data(issue("octocat/hello-world", 12, "Fix the typo").utf8)) as! [String: Any]
        let item = GitHubItems.item(json, role: .assigned)!
        let key = SourceKind.github.key(item.id)
        XCTAssertEqual(key, "github:octocat/hello-world#12")
        XCTAssertEqual(SourceRowText.origin(key).kind, .github)
        XCTAssertEqual(SourceRowText.origin(key).id, "octocat/hello-world#12")
        XCTAssertEqual(SourceRowText.title(from: key), "From GitHub · octocat/hello-world#12")
        XCTAssertEqual(GitHubItems.split(item.id)?.owner, "octocat")
        XCTAssertEqual(GitHubItems.split(item.id)?.repo, "hello-world")
        XCTAssertEqual(GitHubItems.split(item.id)?.number, 12)
    }

    func testAnIdSplitsOnlyWhenItIsSafeToPutInAnAddress() {
        XCTAssertNil(GitHubItems.split("octocat/hello-world"))
        XCTAssertNil(GitHubItems.split("octocat#12"))
        XCTAssertNil(GitHubItems.split("oc tocat/hello#12"))
        XCTAssertNil(GitHubItems.split("octocat/he/llo#12"))
        XCTAssertNil(GitHubItems.split("../x/y#1"), "nothing that could walk the address")
    }

    func testARefusedTokenSaysSo() async {
        for status in [401, 403] {
            do {
                _ = try await GitHubItems(token: "bad", http: ScriptedHTTP([("", status)])).user()
                XCTFail("Expected a refusal")
            } catch {
                XCTAssertEqual(error as? SourceError, .unauthorized)
            }
        }
    }
}

@MainActor
final class GitHubSourceTests: XCTestCase {
    private func issue(_ number: Int, _ title: String, pull: Bool, state: String = "open", merged: Bool = false) -> String {
        let pullText = pull ? ", \"pull_request\": {\"merged_at\": \(merged ? "\"2026-11-06T10:00:00Z\"" : "null")}" : ""
        return """
        {"number": \(number), "title": "\(title)", "state": "\(state)", "html_url": "https://github.com/octocat/hello-world/issues/\(number)", \
        "updated_at": "2026-11-05T10:00:00Z", "repository_url": "https://api.github.com/repos/octocat/hello-world"\(pullText)}
        """
    }

    private func found(_ issues: String...) -> String {
        "{\"total_count\": \(issues.count), \"incomplete_results\": false, \"items\": [\(issues.joined(separator: ","))]}"
    }

    private func store(_ http: HTTP) -> SourceStore {
        SourceStore(defaults: UserDefaults(suiteName: "gh-\(UUID().uuidString)")!, tokens: MemoryTokens(), http: http)
    }

    func testTheRootShowsReviewRequestsThenAssignedIssuesThenYourPullRequests() async {
        let http = ScriptedHTTP([
            (found(issue(5, "Review me", pull: true)), 200),
            (found(issue(2, "Assigned to me", pull: false), issue(9, "Also assigned", pull: false)), 200),
            (found(issue(7, "My pull request", pull: true)), 200),
        ])
        let store = store(http)
        await store.connectGitHub(name: "", token: "t")
        let queries = http.asked.map { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value }
        XCTAssertEqual(queries, ["is:open is:pr review-requested:@me", "is:open is:issue assignee:@me", "is:open is:pr author:@me"])
        let account = store.accounts[0]
        XCTAssertEqual(account.name, "GitHub")
        XCTAssertEqual(account.items.map(\.role), [.reviewRequest, .assigned, .assigned, .mine])
        let root = Root(account, now: Date())
        XCTAssertEqual(root.items.map(\.title), ["Review me", "Assigned to me", "Also assigned"])
        XCTAssertEqual(root.more, 1)
        XCTAssertTrue(root.leaf, "a review request needs you now")
    }

    func testAPullRequestOfYoursUpForReviewShowsOnceAsAReviewRequest() async {
        let http = ScriptedHTTP([
            (found(issue(5, "Review me", pull: true)), 200), (found(), 200), (found(issue(5, "Review me", pull: true)), 200),
        ])
        let store = store(http)
        await store.connectGitHub(name: "Work", token: "t")
        XCTAssertEqual(store.accounts[0].items.map(\.role), [.reviewRequest])
    }

    func testEachSearchSendsItsTagAndKeepsItsItemsWhenNothingChanged() async {
        let http = ScriptedHTTP(headed: [
            (found(issue(5, "Review me", pull: true)), 200, ["ETag": "\"r1\""]),
            (found(issue(2, "Assigned", pull: false)), 200, ["etag": "\"a1\""]),
            (found(), 200, [:]),
            ("", 304, [:]),
            (found(issue(2, "Assigned, renamed", pull: false)), 200, ["ETag": "\"a2\""]),
            (found(issue(7, "Mine", pull: true)), 200, ["ETag": "\"m1\""]),
        ])
        let store = store(http)
        await store.connectGitHub(name: "Work", token: "t")
        await store.refresh()
        let tags = http.asked.map { $0.value(forHTTPHeaderField: "If-None-Match") }
        XCTAssertEqual(tags, [nil, nil, nil, "\"r1\"", "\"a1\"", nil])
        XCTAssertEqual(store.accounts[0].items.map(\.title), ["Review me", "Assigned, renamed", "Mine"])
        XCTAssertNil(store.problems[store.accounts[0].id])
    }

    func testAClosedItemOutsideTheSearchesIsLookedUpAndADeletedOneIsGone() async {
        let http = ScriptedHTTP([
            (found(issue(5, "Review me", pull: true)), 200), (found(), 200), (found(), 200),
            (issue(7, "Shipped", pull: true, state: "closed", merged: true), 200),
            (issue(2, "Renamed since planting", pull: false), 200),
            ("{\"message\": \"Not Found\"}", 404),
        ])
        let store = store(http)
        await store.connectGitHub(name: "Work", token: "t")
        let found = await store.sightings(for: [
            ("github:octocat/hello-world#5", nil), ("github:octocat/hello-world#7", nil),
            ("github:octocat/hello-world#2", nil), ("github:octocat/hello-world#99", nil),
        ])
        XCTAssertEqual(http.asked.count, 6, "the three searches, then one read per item outside them")
        XCTAssertEqual(http.asked[3].url?.path, "/repos/octocat/hello-world/issues/7")
        guard case .seen(let open) = found["github:octocat/hello-world#5"], case .seen(let merged) = found["github:octocat/hello-world#7"],
              case .seen(let renamed) = found["github:octocat/hello-world#2"]
        else { return XCTFail("Expected all three seen: \(found)") }
        XCTAssertTrue(open.todo)
        XCTAssertFalse(merged.todo)
        XCTAssertEqual(renamed.title, "Renamed since planting")
        XCTAssertEqual(found["github:octocat/hello-world#99"], .gone)
    }

    func testARefusedTokenForgetsTheTags() async {
        let http = ScriptedHTTP(headed: [
            (found(), 200, ["ETag": "\"r1\""]), (found(), 200, [:]), (found(), 200, [:]),
            ("", 401, [:]),
            (found(), 200, [:]), (found(), 200, [:]), (found(), 200, [:]),
        ])
        let store = store(http)
        let config = await store.connectGitHub(name: "Work", token: "t")
        await store.refresh()
        XCTAssertEqual(store.problems[config.id], "The token was refused. Sign in again on this device.")
        await store.signIn(config.id, token: "t2")
        XCTAssertNil(http.asked[4].value(forHTTPHeaderField: "If-None-Match"), "signed in again, the searches start afresh")
        XCTAssertNil(store.problems[config.id])
    }
}

final class GitHubLiveRulesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var stamp: String { ISO8601DateFormatter().string(from: now) }
    private let bud = Bud(text: "Fix the typo", state: .open, from: "github:octocat/hello-world#12")
    private func pull(_ title: String = "Fix the typo", todo: Bool = true, cancelled: Bool = false) -> SourceItem {
        SourceItem(id: "octocat/hello-world#12", title: title, detail: "octocat/hello-world · Pull request", todo: todo, cancelled: cancelled)
    }

    func testMergedTicksTheBudAndReopenedOpensIt() {
        let merged = LiveRules.changes(for: bud, kind: .github, sighting: .seen(pull(todo: false)), last: SourceSnapshot(pull()), now: now)
        XCTAssertEqual(merged.changes, [.state(.done), .mark("closed \(stamp)")])
        let back = LiveRules.changes(
            for: Bud(text: "Fix the typo", state: .done, from: "github:octocat/hello-world#12", fromState: "closed"), kind: .github,
            sighting: .seen(pull()), last: merged.seen, now: now)
        XCTAssertEqual(back.changes, [.state(.open), .mark("reopened \(stamp)")])
    }

    func testClosedWithoutMergingTicksTheBudAndSaysCancelled() {
        let result = LiveRules.changes(
            for: bud, kind: .github, sighting: .seen(pull(todo: false, cancelled: true)), last: SourceSnapshot(pull()), now: now)
        XCTAssertEqual(result.changes, [.state(.done), .mark("cancelled")])
    }

    func testANewTitleRenamesTheBud() {
        let result = LiveRules.changes(for: bud, kind: .github, sighting: .seen(pull("Fix the typo in the README")), last: SourceSnapshot(pull()), now: now)
        XCTAssertEqual(result.changes, [.rename("Fix the typo in the README"), .mark("renamed \(stamp)")])
    }

    func testGoneMarksTheBudGone() {
        let result = LiveRules.changes(for: bud, kind: .github, sighting: .gone, last: SourceSnapshot(pull()), now: now)
        XCTAssertEqual(result.changes, [.mark("gone")])
    }
}
