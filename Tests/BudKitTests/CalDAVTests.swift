import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import BudKit

final class CalDAVTests: XCTestCase {
    private let server = URL(string: "https://cal.example.org/")!

    func testEventsReadTheirUidSummaryStartPlaceAndStatus() throws {
        let text = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:ev-1\r\nSUMMARY:Flat viewing\\, Elm Street\r\nDTSTART:20261106T090000Z\r\nLOCATION:Elm \r\n Street 4\r\nEND:VEVENT\r\n"
            + "BEGIN:VEVENT\r\nUID:ev-2\r\nSUMMARY:Dentist\r\nSTATUS:CANCELLED\r\nDTSTART;TZID=Europe/Lisbon:20261107T100000\r\nEND:VEVENT\r\n"
            + "BEGIN:VEVENT\r\nUID:ev-3\r\nRECURRENCE-ID:20261108T080000Z\r\nDTSTART;VALUE=DATE:20261108\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
        let events = ICS.events(in: text)
        XCTAssertEqual(events.map(\.uid), ["ev-1", "ev-2", "ev-3"])
        XCTAssertEqual(events[0].summary, "Flat viewing, Elm Street")
        XCTAssertEqual(events[0].location, "Elm Street 4")
        XCTAssertEqual(events[0].start, Date(timeIntervalSince1970: 1_793_955_600))
        XCTAssertTrue(events[1].cancelled)
        let lisbon = try XCTUnwrap(TimeZone(identifier: "Europe/Lisbon"))
        let expected = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: lisbon, year: 2026, month: 11, day: 7, hour: 10).date
        XCTAssertEqual(events[1].start, expected)
        XCTAssertEqual(events[2].summary, "Untitled event")
        XCTAssertEqual(events[2].item.id, "ev-3/20261108T080000Z")
        XCTAssertNotNil(events[2].start)
    }

    func testDiscoveryFollowsThePrincipalToTheCalendarsThatHoldEvents() async throws {
        let principal = """
        <d:multistatus xmlns:d="DAV:"><d:response><d:href>/</d:href><d:propstat><d:prop>
        <d:current-user-principal><d:href>/principals/sam/</d:href></d:current-user-principal>
        </d:prop></d:propstat></d:response></d:multistatus>
        """
        let home = """
        <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:response><d:href>/principals/sam/</d:href>
        <d:propstat><d:prop><c:calendar-home-set><d:href>/calendars/sam/</d:href></c:calendar-home-set></d:prop></d:propstat>
        </d:response></d:multistatus>
        """
        let list = """
        <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:response><d:href>/calendars/sam/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
          <d:response><d:href>/calendars/sam/home/</d:href><d:propstat><d:prop><d:displayname>Home</d:displayname>
            <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
            <c:supported-calendar-component-set><c:comp name="VEVENT"/></c:supported-calendar-component-set></d:prop></d:propstat></d:response>
          <d:response><d:href>/calendars/sam/chores/</d:href><d:propstat><d:prop><d:displayname>Chores</d:displayname>
            <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
            <c:supported-calendar-component-set><c:comp name="VTODO"/></c:supported-calendar-component-set></d:prop></d:propstat></d:response>
          <d:response><d:href>/calendars/sam/away/</d:href><d:propstat><d:prop><d:displayname>Away</d:displayname>
            <d:resourcetype><d:collection/><c:calendar/></d:resourcetype></d:prop></d:propstat></d:response>
        </d:multistatus>
        """
        let http = ScriptedHTTP([(principal, 207), (home, 207), (list, 207)])
        let cal = CalDAV(server: server, user: "sam", password: "app-pass", http: http)
        let calendars = try await cal.calendars()
        XCTAssertEqual(calendars.map(\.name), ["Away", "Home"])
        XCTAssertEqual(calendars.last?.url.absoluteString, "https://cal.example.org/calendars/sam/home/")
        XCTAssertEqual(http.asked.map(\.httpMethod), ["PROPFIND", "PROPFIND", "PROPFIND"])
        XCTAssertEqual(http.asked[1].url?.absoluteString, "https://cal.example.org/principals/sam/")
        XCTAssertEqual(http.asked[2].value(forHTTPHeaderField: "Depth"), "1")
        XCTAssertEqual(http.asked[0].value(forHTTPHeaderField: "Authorization"), "Basic " + Data("sam:app-pass".utf8).base64EncodedString())
    }

    func testTheWindowLeavesCancelledEventsOut() async throws {
        let report = """
        <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:response><d:href>/calendars/sam/home/a.ics</d:href><d:propstat><d:prop><c:calendar-data>BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:a
        SUMMARY:Flight to Lisbon
        DTSTART:20261110T070000Z
        END:VEVENT
        END:VCALENDAR</c:calendar-data></d:prop></d:propstat></d:response>
          <d:response><d:href>/calendars/sam/home/b.ics</d:href><d:propstat><d:prop><c:calendar-data>BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:b
        SUMMARY:Flat viewing
        STATUS:CANCELLED
        DTSTART:20261106T090000Z
        END:VEVENT
        END:VCALENDAR</c:calendar-data></d:prop></d:propstat></d:response>
        </d:multistatus>
        """
        let http = ScriptedHTTP([(report, 207)])
        let cal = CalDAV(server: server, user: "sam", password: "p", http: http)
        let items = try await cal.window(of: URL(string: "https://cal.example.org/calendars/sam/home/")!, now: Date(timeIntervalSince1970: 1_793_900_000))
        XCTAssertEqual(items.map(\.title), ["Flight to Lisbon"])
        XCTAssertEqual(http.asked.first?.httpMethod, "REPORT")
        let body = String(data: http.asked.first?.httpBody ?? Data(), encoding: .utf8) ?? ""
        let start = CalDAV.stamp(Date(timeIntervalSince1970: 1_793_900_000))
        let end = CalDAV.stamp(Date(timeIntervalSince1970: 1_793_900_000 + 14 * 86_400))
        XCTAssertTrue(body.contains("<c:expand start=\"\(start)\" end=\"\(end)\"/>"), body)
        XCTAssertEqual(start.count, 16)
    }

    func testTheSyncTokenIsReadFromTheCalendar() async throws {
        let reply = """
        <d:multistatus xmlns:d="DAV:"><d:response><d:href>/calendars/sam/home/</d:href><d:propstat><d:prop>
        <d:sync-token>http://example.org/sync/42</d:sync-token></d:prop></d:propstat></d:response></d:multistatus>
        """
        let cal = CalDAV(server: server, user: "sam", password: "p", http: ScriptedHTTP([(reply, 207)]))
        let token = try await cal.syncToken(of: URL(string: "https://cal.example.org/calendars/sam/home/")!)
        XCTAssertEqual(token, "http://example.org/sync/42")
    }

    func testARefusedPasswordSaysSo() async {
        let cal = CalDAV(server: server, user: "sam", password: "wrong", http: ScriptedHTTP([("", 401)]))
        do {
            _ = try await cal.calendars()
            XCTFail("Expected a refusal")
        } catch {
            XCTAssertEqual(error as? SourceError, .unauthorized)
        }
    }
}
