import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import BudKit

/// A server that answers each request from a script, and keeps what it was asked.
final class ScriptedHTTP: HTTP, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [(Data, Int)]
    private(set) var asked: [URLRequest] = []

    init(_ replies: [(String, Int)]) { self.replies = replies.map { (Data($0.0.utf8), $0.1) } }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        lock.lock(); defer { lock.unlock() }
        asked.append(request)
        return replies.isEmpty ? (Data(), 500) : replies.removeFirst()
    }

    func body(_ i: Int) -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        guard let data = asked[i].httpBody else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

final class JMAPMailTests: XCTestCase {
    private let sessionURL = URL(string: "https://mail.example.org/jmap/session")!
    private let session = """
    {"apiUrl": "https://mail.example.org/jmap/api/", "primaryAccounts": {"urn:ietf:params:jmap:mail": "A1"}}
    """

    func testTheSessionNamesTheAPIAndTheAccount() async throws {
        let http = ScriptedHTTP([(session, 200)])
        let mail = JMAPMail(session: sessionURL, token: "secret", http: http)
        let endpoint = try await mail.endpoint()
        XCTAssertEqual(endpoint.api.absoluteString, "https://mail.example.org/jmap/api/")
        XCTAssertEqual(endpoint.account, "A1")
        XCTAssertEqual(http.asked.first?.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    }

    func testARefusedTokenSaysSo() async {
        let mail = JMAPMail(session: sessionURL, token: "wrong", http: ScriptedHTTP([("", 401)]))
        do {
            _ = try await mail.endpoint()
            XCTFail("Expected a refusal")
        } catch {
            XCTAssertEqual(error as? SourceError, .unauthorized)
        }
    }

    func testMailboxesPutTheInboxFirst() async throws {
        let reply = """
        {"methodResponses": [["Mailbox/get", {"list": [
            {"id": "b2", "name": "Archive", "role": "archive"},
            {"id": "b3", "name": "Bills", "role": null},
            {"id": "b1", "name": "Inbox", "role": "inbox"}
        ], "state": "s"}, "m"]]}
        """
        let mail = JMAPMail(session: sessionURL, token: "t", http: ScriptedHTTP([(reply, 200)]))
        let boxes = try await mail.mailboxes(at: .init(api: URL(string: "https://mail.example.org/api")!, account: "A1"))
        XCTAssertEqual(boxes.map(\.name), ["Inbox", "Archive", "Bills"])
    }

    func testTheWindowReadsSubjectSenderUnreadAndFlag() async throws {
        let reply = """
        {"methodResponses": [
            ["Email/query", {"ids": ["e1", "e2", "e3"]}, "q"],
            ["Email/get", {"state": "S9", "list": [
                {"id": "e1", "subject": "Paper samples are ready", "from": [{"name": "Northside Print", "email": "hello@example.org"}],
                 "receivedAt": "2026-11-05T09:30:00Z", "keywords": {}},
                {"id": "e2", "subject": "Lease renewal draft", "from": [{"name": "", "email": "letting@example.org"}],
                 "receivedAt": "2026-11-04T09:30:00Z", "keywords": {"$seen": true, "$flagged": true}},
                {"id": "e3", "subject": "", "from": null, "receivedAt": "2026-11-03T09:30:00Z", "keywords": {"$seen": true}}
            ]}, "g"]
        ]}
        """
        let http = ScriptedHTTP([(reply, 200)])
        let mail = JMAPMail(session: sessionURL, token: "t", http: http)
        let window = try await mail.window(at: .init(api: URL(string: "https://mail.example.org/api")!, account: "A1"), mailbox: "b1")
        XCTAssertEqual(window.state, "S9")
        XCTAssertEqual(window.items.map(\.title), ["Paper samples are ready", "Lease renewal draft", "No subject"])
        XCTAssertEqual(window.items.map(\.detail), ["Northside Print", "letting@example.org", nil])
        XCTAssertEqual(window.items.map(\.unread), [true, false, false])
        XCTAssertEqual(window.items.map(\.todo), [false, true, false])
        XCTAssertNotNil(window.items[0].date)
        let calls = http.body(0)["methodCalls"] as? [[Any]]
        XCTAssertEqual(calls?.first?.first as? String, "Email/query")
        XCTAssertEqual((calls?.first?[1] as? [String: Any])?["filter"] as? [String: String], ["inMailbox": "b1"])
    }

    func testChangesAreAskedSinceTheLastState() async throws {
        let endpoint = JMAPMail.Endpoint(api: URL(string: "https://mail.example.org/api")!, account: "A1")
        let none = """
        {"methodResponses": [["Email/changes", {"oldState": "S9", "newState": "S9", "created": [], "updated": [], "destroyed": []}, "c"]]}
        """
        let some = """
        {"methodResponses": [["Email/changes", {"oldState": "S9", "newState": "S10", "created": ["e4"], "updated": [], "destroyed": []}, "c"]]}
        """
        let lost = """
        {"methodResponses": [["error", {"type": "cannotCalculateChanges"}, "c"]]}
        """
        let mail = JMAPMail(session: sessionURL, token: "t", http: ScriptedHTTP([(none, 200), (some, 200), (lost, 200)]))
        let first = try await mail.changed(at: endpoint, since: "S9")
        let second = try await mail.changed(at: endpoint, since: "S9")
        let third = try await mail.changed(at: endpoint, since: "S9")
        XCTAssertFalse(first)
        XCTAssertTrue(second)
        XCTAssertTrue(third)
    }
}
