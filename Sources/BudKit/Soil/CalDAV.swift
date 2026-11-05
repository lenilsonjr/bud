import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Calendars over CalDAV: a server, a user name and an app password find the calendars; Bud
/// reads the next 14 days of one, and asks the calendar's sync token first, reading again only
/// when it moved.
public struct CalDAV: Sendable {
    public struct Calendar: Hashable, Sendable, Identifiable {
        public let url: URL
        public let name: String
        public var id: URL { url }
    }

    public let server: URL
    public let user: String
    public let password: String
    public let http: HTTP
    /// How far ahead the window reaches.
    public var days = 14

    public init(server: URL, user: String, password: String, http: HTTP = NetworkHTTP()) {
        self.server = server
        self.user = user
        self.password = password
        self.http = http
    }

    /// The calendars that hold events, by name.
    public func calendars() async throws -> [Calendar] {
        let principal = try await href(
            at: server, depth: 0,
            prop: "<d:current-user-principal/>", inside: "current-user-principal")
        let home = try await href(
            at: principal, depth: 0,
            prop: "<c:calendar-home-set/>", inside: "calendar-home-set")
        let tree = try await xml(
            "PROPFIND", at: home, depth: 1,
            body: Self.propfind("<d:displayname/><d:resourcetype/><c:supported-calendar-component-set/>"))
        let calendars = tree.all("response").compactMap { response -> Calendar? in
            guard let path = response.first("href")?.text, response.first("resourcetype")?.first("calendar") != nil else { return nil }
            let comps = response.first("supported-calendar-component-set")?.all("comp").compactMap { $0.attributes["name"] } ?? ["VEVENT"]
            guard comps.contains("VEVENT"), let url = URL(string: path, relativeTo: home)?.absoluteURL else { return nil }
            let name = response.first("displayname")?.text ?? url.lastPathComponent
            return Calendar(url: url, name: name.isEmpty ? url.lastPathComponent : name)
        }
        return calendars.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The calendar's sync token, which moves whenever an event in it changes.
    public func syncToken(of calendar: URL) async throws -> String? {
        let tree = try await xml("PROPFIND", at: calendar, depth: 0, body: Self.propfind("<d:sync-token/><cs:getctag/>"))
        return tree.first("sync-token")?.text ?? tree.first("getctag")?.text
    }

    /// The events from `now` to `days` ahead, repeats expanded by the server, cancelled ones marked.
    public func window(of calendar: URL, now: Date) async throws -> [SourceItem] {
        let start = Self.stamp(now), end = Self.stamp(now.addingTimeInterval(Double(days) * 86_400))
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:prop><c:calendar-data><c:expand start="\(start)" end="\(end)"/></c:calendar-data></d:prop>
          <c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT">
            <c:time-range start="\(start)" end="\(end)"/>
          </c:comp-filter></c:comp-filter></c:filter>
        </c:calendar-query>
        """
        let tree = try await xml("REPORT", at: calendar, depth: 1, body: body)
        return tree.all("calendar-data").flatMap { ICS.events(in: $0.text) }.map(\.item)
    }

    // MARK: requests

    private func href(at url: URL, depth: Int, prop: String, inside name: String) async throws -> URL {
        let tree = try await xml("PROPFIND", at: url, depth: depth, body: Self.propfind(prop))
        guard let path = tree.first(name)?.first("href")?.text, let found = URL(string: path, relativeTo: url)?.absoluteURL else {
            throw SourceError.unreadable(name)
        }
        return found
    }

    private func xml(_ method: String, at url: URL, depth: Int, body: String) async throws -> XMLNode {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("\(depth)", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic \(Data("\(user):\(password)".utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(body.utf8)
        let (data, status) = try await http.send(request)
        if status == 401 || status == 403 { throw SourceError.unauthorized }
        guard (200..<300).contains(status) else { throw SourceError.status(status) }
        guard let tree = XMLNode.parse(data) else { throw SourceError.unreadable(method) }
        return tree
    }

    private static func propfind(_ props: String) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/">
          <d:prop>\(props)</d:prop>
        </d:propfind>
        """
    }

    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }
}

/// A parsed XML element: its local name without the namespace prefix, attributes, children and text.
final class XMLNode: @unchecked Sendable {
    let name: String
    var attributes: [String: String]
    var children: [XMLNode] = []
    var text = ""

    init(name: String, attributes: [String: String] = [:]) {
        self.name = name
        self.attributes = attributes
    }

    /// The first element of this name at any depth, this one included.
    func first(_ name: String) -> XMLNode? {
        if self.name == name { return self }
        for child in children { if let found = child.first(name) { return found } }
        return nil
    }

    /// Every element of this name at any depth, in document order.
    func all(_ name: String) -> [XMLNode] {
        (self.name == name ? [self] : []) + children.flatMap { $0.all(name) }
    }

    static func parse(_ data: Data) -> XMLNode? {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        guard parser.parse() else { return nil }
        return builder.root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XMLNode?
        var stack: [XMLNode] = []

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            let local = name.split(separator: ":").last.map(String.init) ?? name
            let node = XMLNode(name: local, attributes: attributes)
            stack.last?.children.append(node)
            if root == nil { root = node }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if let node = stack.popLast() { node.text = node.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }

        func parser(_ parser: XMLParser, foundCDATA data: Data) {
            stack.last?.text += String(decoding: data, as: UTF8.self)
        }
    }
}

/// Just enough iCalendar to read events: the uid, summary, start, location and status.
enum ICS {
    struct Event: Equatable {
        var uid: String
        var recurrence: String?
        var summary: String
        var start: Date?
        var location: String?
        var cancelled: Bool

        /// One occurrence is one item: a repeat carries its occurrence in the id.
        var item: SourceItem {
            let id = recurrence.map { "\(uid)/\($0)" } ?? uid
            return SourceItem(id: id, title: summary, detail: location, date: start, cancelled: cancelled)
        }
    }

    static func events(in text: String) -> [Event] {
        var events: [Event] = []
        var current: Event?
        for line in unfold(text) {
            let (name, params, value) = split(line)
            switch name {
            case "BEGIN" where value == "VEVENT":
                current = Event(uid: "", summary: "Untitled event", cancelled: false)
            case "END" where value == "VEVENT":
                if let event = current, !event.uid.isEmpty { events.append(event) }
                current = nil
            case "UID": current?.uid = value
            case "RECURRENCE-ID": current?.recurrence = value
            case "SUMMARY": if !value.isEmpty { current?.summary = unescape(value) }
            case "LOCATION": current?.location = value.isEmpty ? nil : unescape(value)
            case "STATUS": current?.cancelled = value.uppercased() == "CANCELLED"
            case "DTSTART": current?.start = date(value, params: params)
            default: break
            }
        }
        return events
    }

    /// A long line continues on the next one after a space or a tab.
    static func unfold(_ text: String) -> [String] {
        var lines: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else {
                lines.append(String(raw))
            }
        }
        return lines
    }

    /// `DTSTART;TZID=Europe/Lisbon:20261106T090000` into its name, parameters and value.
    static func split(_ line: String) -> (String, [String: String], String) {
        guard let colon = line.firstIndex(of: ":") else { return (line, [:], "") }
        let head = line[..<colon].split(separator: ";").map(String.init)
        var params: [String: String] = [:]
        for part in head.dropFirst() {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { params[pair[0].uppercased()] = pair[1] }
        }
        return ((head.first ?? "").uppercased(), params, String(line[line.index(after: colon)...]))
    }

    /// UTC with a Z, local to TZID, or floating in this device's zone; a date alone is midnight.
    static func date(_ value: String, params: [String: String]) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if value.count == 8 || params["VALUE"] == "DATE" {
            formatter.dateFormat = "yyyyMMdd"
            formatter.timeZone = .current
            return formatter.date(from: String(value.prefix(8)))
        }
        if value.hasSuffix("Z") {
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        } else {
            formatter.timeZone = params["TZID"].flatMap(TimeZone.init(identifier:)) ?? .current
            formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        }
        return formatter.date(from: value)
    }

    static func unescape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\N", with: " ")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
