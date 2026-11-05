import XCTest
@testable import BudKit

@MainActor
final class SourceStoreTests: XCTestCase {
    private let session = URL(string: "https://mail.example.org/jmap/session")!
    private let sessionReply = """
    {"apiUrl": "https://mail.example.org/jmap/api/", "primaryAccounts": {"urn:ietf:params:jmap:mail": "A1"}}
    """
    private func window(_ state: String, _ subjects: [String]) -> String {
        let list = subjects.enumerated().map { i, s in
            "{\"id\": \"e\(i)\", \"subject\": \"\(s)\", \"from\": [{\"name\": \"Sam\"}], \"receivedAt\": \"2026-11-05T09:0\(i):00Z\", \"keywords\": {}}"
        }.joined(separator: ",")
        return "{\"methodResponses\": [[\"Email/query\", {}, \"q\"], [\"Email/get\", {\"state\": \"\(state)\", \"list\": [\(list)]}, \"g\"]]}"
    }
    private let unchanged = """
    {"methodResponses": [["Email/changes", {"oldState": "S1", "newState": "S1", "created": [], "updated": [], "destroyed": []}, "c"]]}
    """

    private func defaults() -> UserDefaults {
        let name = "sources-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testConnectingMailReadsItsWindowAndKeepsTheTokenOffTheList() async throws {
        let tokens = MemoryTokens()
        let defaults = defaults()
        let http = ScriptedHTTP([(sessionReply, 200), (window("S1", ["Paper samples", "Lease draft"]), 200)])
        let store = SourceStore(defaults: defaults, tokens: tokens, http: http)
        let config = await store.connectMail(name: "Work mail", session: session, token: "secret", mailbox: "b1")
        XCTAssertEqual(store.accounts.map(\.name), ["Work mail"])
        XCTAssertEqual(store.accounts.first?.items.map(\.title), ["Paper samples", "Lease draft"])
        XCTAssertFalse(store.accounts.first?.locked ?? true)
        XCTAssertEqual(tokens.token(for: config.id), "secret")
        let saved = String(data: defaults.data(forKey: SourceStore.configsKey) ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(saved.contains("Work mail"))
        XCTAssertFalse(saved.contains("secret"), "the token never joins the list")
    }

    func testAnAccountWithoutATokenOnThisDeviceIsLocked() async {
        let defaults = defaults()
        let first = SourceStore(defaults: defaults, tokens: MemoryTokens(), http: ScriptedHTTP([(sessionReply, 200), (window("S1", ["x"]), 200)]))
        await first.connectMail(name: "Mail", session: session, token: "secret", mailbox: "b1")
        let elsewhere = SourceStore(defaults: defaults, tokens: MemoryTokens(), http: ScriptedHTTP([]))
        await elsewhere.refresh()
        XCTAssertEqual(elsewhere.accounts.count, 1)
        XCTAssertTrue(elsewhere.accounts[0].locked)
        XCTAssertEqual(Root(elsewhere.accounts[0]).items, [])
    }

    func testARefreshWithNoChangesKeepsTheWindowWithoutReadingIt() async {
        let http = ScriptedHTTP([(sessionReply, 200), (window("S1", ["Paper samples"]), 200), (unchanged, 200)])
        let store = SourceStore(defaults: defaults(), tokens: MemoryTokens(), http: http)
        await store.connectMail(name: "Mail", session: session, token: "t", mailbox: "b1")
        await store.refresh()
        XCTAssertEqual(http.asked.count, 3, "session, window, then only changes")
        XCTAssertEqual(store.accounts.first?.items.map(\.title), ["Paper samples"])
    }

    func testARefusedTokenIsReported() async {
        let store = SourceStore(defaults: defaults(), tokens: MemoryTokens(), http: ScriptedHTTP([("", 401)]))
        let config = await store.connectMail(name: "Mail", session: session, token: "old", mailbox: "b1")
        XCTAssertEqual(store.problems[config.id], "The token was refused. Sign in again on this device.")
    }

    func testDisconnectingForgetsTheAccountAndItsToken() async {
        let tokens = MemoryTokens()
        let store = SourceStore(defaults: defaults(), tokens: tokens, http: ScriptedHTTP([(sessionReply, 200), (window("S1", ["x"]), 200)]))
        let config = await store.connectMail(name: "Mail", session: session, token: "t", mailbox: "b1")
        store.disconnect(config.id)
        XCTAssertEqual(store.accounts, [])
        XCTAssertNil(tokens.token(for: config.id))
    }
}

final class SourcesTextTests: XCTestCase {
    func testTheStatusLineCountsItemsOrSaysWhereTheAccountLives() {
        XCTAssertEqual(SourcesText.status(SourceAccount(id: "a", kind: .mail, locked: true)), "Connected on another device")
        XCTAssertEqual(SourcesText.status(SourceAccount(id: "a", kind: .mail, items: [SourceItem(id: "1", title: "x")])), "1 item")
        XCTAssertEqual(SourcesText.status(SourceAccount(id: "a", kind: .mail)), "0 items")
    }

    func testProblemsAreSaidPlainly() {
        XCTAssertEqual(SourcesText.problem(SourceError.unauthorized), "The token was refused.")
        XCTAssertEqual(SourcesText.problem(SourceError.unreadable("x")), "That address did not answer as expected.")
        XCTAssertEqual(SourcesText.problem(SourceError.status(500)), "Couldn't reach that address.")
    }
}

@MainActor
final class CalendarSourceTests: XCTestCase {
    private let server = URL(string: "https://cal.example.org/")!
    private let calendar = URL(string: "https://cal.example.org/calendars/sam/home/")!
    private func token(_ value: String) -> String {
        "<d:multistatus xmlns:d=\"DAV:\"><d:response><d:propstat><d:prop><d:sync-token>\(value)</d:sync-token></d:prop></d:propstat></d:response></d:multistatus>"
    }
    private func report(_ title: String) -> String {
        "<d:multistatus xmlns:d=\"DAV:\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\"><d:response><d:propstat><d:prop><c:calendar-data>BEGIN:VEVENT\nUID:\(title)\nSUMMARY:\(title)\nDTSTART:20261110T070000Z\nEND:VEVENT</c:calendar-data></d:prop></d:propstat></d:response></d:multistatus>"
    }

    func testACalendarIsReadAgainOnlyWhenItsTokenMovesOrAnHourPasses() async {
        let http = ScriptedHTTP([
            (token("1"), 207), (report("Dentist"), 207),
            (token("1"), 207),
            (token("2"), 207), (report("Flight"), 207),
            (token("2"), 207), (report("Flight"), 207),
        ])
        let defaults = UserDefaults(suiteName: "cal-\(UUID().uuidString)")!
        let store = SourceStore(defaults: defaults, tokens: MemoryTokens(), http: http)
        var now = Date(timeIntervalSince1970: 1_793_900_000)
        store.clock = { now }
        await store.connectCalendar(name: "Home", server: server, user: "sam", password: "p", calendar: calendar)
        XCTAssertEqual(store.accounts.first?.items.map(\.title), ["Dentist"])
        await store.refresh()
        XCTAssertEqual(http.asked.count, 3, "same token: no report")
        await store.refresh()
        XCTAssertEqual(store.accounts.first?.items.map(\.title), ["Flight"])
        now += 3601
        await store.refresh()
        XCTAssertEqual(http.asked.count, 7, "an hour on: the window is read again")
        XCTAssertEqual(store.accounts.first?.kind, .calendar)
    }
}

@MainActor
final class SightingTests: XCTestCase {
    func testMailOutsideTheWindowIsAskedForByIdAndMissingMailIsGone() async {
        let session = URL(string: "https://mail.example.org/jmap/session")!
        let sessionReply = """
        {"apiUrl": "https://mail.example.org/jmap/api/", "primaryAccounts": {"urn:ietf:params:jmap:mail": "A1"}}
        """
        let window = """
        {"methodResponses": [["Email/query", {}, "q"], ["Email/get", {"state": "S1", "list": [
            {"id": "e1", "subject": "In the window", "keywords": {}}]}, "g"]]}
        """
        let byId = """
        {"methodResponses": [["Email/get", {"list": [{"id": "e2", "subject": "Filed away", "keywords": {"$seen": true}}], "notFound": ["e3"]}, "g"]]}
        """
        let http = ScriptedHTTP([(sessionReply, 200), (window, 200), (byId, 200)])
        let store = SourceStore(defaults: UserDefaults(suiteName: "s-\(UUID().uuidString)")!, tokens: MemoryTokens(), http: http)
        await store.connectMail(name: "Mail", session: session, token: "t", mailbox: "b1")
        let found = await store.sightings(for: [("mail:e1", nil), ("mail:e2", nil), ("mail:e3", nil), ("calendar:x", nil)])
        XCTAssertEqual(found["mail:e1"], .seen(SourceItem(id: "e1", title: "In the window", unread: true)))
        if case .seen(let item) = found["mail:e2"] { XCTAssertEqual(item.title, "Filed away") } else { XCTFail("e2 not seen") }
        XCTAssertEqual(found["mail:e3"], .gone)
        XCTAssertNil(found["calendar:x"], "no calendar here: nothing is said")
    }
}

@MainActor
final class TwoCalendarTests: XCTestCase {
    func testAnEventInTheSecondCalendarIsSeenNotGone() async {
        func token() -> String {
            "<d:multistatus xmlns:d=\"DAV:\"><d:response><d:propstat><d:prop><d:sync-token>1</d:sync-token></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>"
        }
        func report(_ uid: String) -> String {
            "<d:multistatus xmlns:d=\"DAV:\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\"><d:response><d:propstat><d:prop><c:calendar-data>BEGIN:VEVENT\nUID:\(uid)\nSUMMARY:\(uid)\nDTSTART:20261110T070000Z\nEND:VEVENT</c:calendar-data></d:prop></d:propstat></d:response></d:multistatus>"
        }
        let http = ScriptedHTTP([(token(), 207), (report("home"), 207), (token(), 207), (report("work"), 207)])
        let store = SourceStore(defaults: UserDefaults(suiteName: "two-\(UUID().uuidString)")!, tokens: MemoryTokens(), http: http)
        let now = Date(timeIntervalSince1970: 1_793_900_000)
        store.clock = { now }
        let server = URL(string: "https://cal.example.org/")!
        await store.connectCalendar(name: "Home", server: server, user: "sam", password: "p", calendar: URL(string: "https://cal.example.org/home/")!)
        await store.connectCalendar(name: "Work", server: server, user: "sam", password: "p", calendar: URL(string: "https://cal.example.org/work/")!)
        let soon = now.addingTimeInterval(3 * 86_400)
        let found = await store.sightings(for: [("calendar:work", soon), ("calendar:gone", soon)])
        if case .seen(let item) = found["calendar:work"] { XCTAssertEqual(item.title, "work") } else { XCTFail("work not seen") }
        XCTAssertEqual(found["calendar:gone"], .gone)
    }
}
