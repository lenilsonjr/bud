import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Linear over its GraphQL API: a personal API key reads the open issues assigned to you, and asks
/// what was updated since the last read before reading again.
public struct LinearIssues: Sendable {
    public let token: String
    public let http: HTTP
    public var endpoint = URL(string: "https://api.linear.app/graphql")!
    /// How many issues the window holds: the most Linear gives in one page, so issues due soon are
    /// not left out for being untouched lately.
    public var limit = 250

    public init(token: String, http: HTTP = NetworkHTTP()) {
        self.token = token
        self.http = http
    }

    /// The name of the workspace the key reads, which also checks the key.
    public func workspace() async throws -> String {
        let data = try await query("query { viewer { organization { name } } }")
        guard let name = ((data["viewer"] as? [String: Any])?["organization"] as? [String: Any])?["name"] as? String else {
            throw SourceError.unreadable("viewer")
        }
        return name
    }

    /// The open issues assigned to you, and the newest update among them to ask for changes since.
    public func window() async throws -> (items: [SourceItem], updated: Date?) {
        let data = try await query("""
        query { viewer { assignedIssues(first: \(limit), orderBy: updatedAt, \
        filter: { state: { type: { nin: ["completed", "canceled"] } } }) { nodes { \(Self.fields) } } } }
        """)
        guard let nodes = ((data["viewer"] as? [String: Any])?["assignedIssues"] as? [String: Any])?["nodes"] as? [[String: Any]] else {
            throw SourceError.unreadable("assignedIssues")
        }
        let updated = nodes.compactMap { ($0["updatedAt"] as? String).flatMap(SourceDates.instant) }.max()
        return (nodes.compactMap(Self.item), updated)
    }

    /// When the newest update after `since` to an issue assigned to you was made, closed ones
    /// included; nil when there was none. A reply Bud cannot read counts as an update at `since`,
    /// so the window is read and this device's clock never stands in for Linear's.
    public func changed(since: Date) async throws -> Date? {
        let data = try await query("""
        query { viewer { assignedIssues(first: 1, includeArchived: true, orderBy: updatedAt, \
        filter: { updatedAt: { gt: "\(SourceDates.stamp(since))" } }) { nodes { updatedAt } } } }
        """)
        guard let nodes = ((data["viewer"] as? [String: Any])?["assignedIssues"] as? [String: Any])?["nodes"] as? [[String: Any]] else {
            return since
        }
        guard let newest = nodes.first else { return nil }
        return (newest["updatedAt"] as? String).flatMap(SourceDates.instant) ?? since
    }

    /// Particular issues by identifier, whatever their state or assignee now: the ones found, and
    /// the identifiers this workspace no longer has, deleted or never its own. Archived ones count:
    /// Linear archives closed issues after a while.
    public func issues(_ identifiers: [String]) async throws -> (found: [SourceItem], missing: [String]) {
        let wanted = identifiers.compactMap(Self.split)
        guard !wanted.isEmpty else { return ([], identifiers) }
        let any = wanted.map { "{ team: { key: { eq: \"\($0.team)\" } }, number: { eq: \($0.number) } }" }.joined(separator: ", ")
        let data = try await query("query { issues(first: \(wanted.count), includeArchived: true, filter: { or: [\(any)] }) { nodes { \(Self.fields) } } }")
        guard let nodes = (data["issues"] as? [String: Any])?["nodes"] as? [[String: Any]] else {
            throw SourceError.unreadable("issues")
        }
        let found = nodes.compactMap(Self.item)
        let ids = Set(found.map(\.id))
        return (found, identifiers.filter { !ids.contains($0) })
    }

    static let fields = "identifier title dueDate priority url updatedAt team { key } state { name type }"

    /// One issue as a soil item: its title, the team and state, due date and priority; a to-do
    /// until it is completed or cancelled.
    static func item(_ issue: [String: Any]) -> SourceItem? {
        guard let id = issue["identifier"] as? String else { return nil }
        let title = (issue["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
        let team = (issue["team"] as? [String: Any])?["key"] as? String
        let state = issue["state"] as? [String: Any]
        let type = state?["type"] as? String
        let detail = [team, state?["name"] as? String].compactMap { $0 }.joined(separator: " · ")
        let priority = (issue["priority"] as? NSNumber)?.intValue
        return SourceItem(
            id: id, title: title, detail: detail.isEmpty ? nil : detail,
            date: (issue["dueDate"] as? String).flatMap(Self.day),
            priority: priority == 0 ? nil : priority,
            todo: type != "completed" && type != "canceled", cancelled: type == "canceled",
            url: (issue["url"] as? String).flatMap(URL.init(string:))
        )
    }

    /// `ENG-12` into its team key and number.
    static func split(_ identifier: String) -> (team: String, number: Int)? {
        guard let dash = identifier.lastIndex(of: "-"), let number = Int(identifier[identifier.index(after: dash)...]) else { return nil }
        let team = String(identifier[..<dash])
        guard !team.isEmpty, team.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
        return (team, number)
    }

    /// A due date is a day, midnight here.
    static func day(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    /// Runs a query and hands back its data. A refused key is unauthorized, whether the server says
    /// so with a status or in the errors.
    private func query(_ text: String) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        // A personal API key goes as it is; an OAuth token would carry Bearer.
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": text])
        let (body, status) = try await http.send(request)
        if status == 401 || status == 403 { throw SourceError.unauthorized }
        let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        if let errors = json?["errors"] as? [[String: Any]], errors.contains(where: Self.refused) { throw SourceError.unauthorized }
        guard (200..<300).contains(status) else { throw SourceError.status(status) }
        guard let data = json?["data"] as? [String: Any] else { throw SourceError.unreadable("data") }
        return data
    }

    private static func refused(_ error: [String: Any]) -> Bool {
        let code = (error["extensions"] as? [String: Any])?["code"] as? String
        return code == "AUTHENTICATION_ERROR" || code == "FORBIDDEN"
    }
}
