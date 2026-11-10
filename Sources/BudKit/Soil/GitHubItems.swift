import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// GitHub over its REST API: a fine-grained personal access token reads the pull requests waiting
/// for your review, the issues assigned to you and your own open pull requests, and asks each
/// search whether anything changed, by ETag, before reading it again.
public struct GitHubItems: Sendable {
    public let token: String
    public let http: HTTP
    public var api = URL(string: "https://api.github.com")!
    /// How many items one search holds: the most GitHub gives in one page.
    public var limit = 100

    public init(token: String, http: HTTP = NetworkHTTP()) {
        self.token = token
        self.http = http
    }

    /// The three searches the root shows, in its order.
    public enum Query: String, CaseIterable, Sendable {
        case reviews, assigned, mine

        /// What GitHub is asked for.
        public var text: String {
            switch self {
            case .reviews: return "is:open is:pr review-requested:@me"
            case .assigned: return "is:open is:issue assignee:@me"
            case .mine: return "is:open is:pr author:@me"
            }
        }

        /// Why its items are in front of you.
        public var role: SourceItem.Role {
            switch self {
            case .reviews: return .reviewRequest
            case .assigned: return .assigned
            case .mine: return .mine
            }
        }
    }

    /// The login the token signs in as, which also checks the token.
    public func user() async throws -> String {
        let reply = try await get(api.appendingPathComponent("user"))
        guard (200..<300).contains(reply.status) else { throw SourceError.status(reply.status) }
        guard let login = Self.json(reply)?["login"] as? String else { throw SourceError.unreadable("login") }
        return login
    }

    /// One search's open items, newest update first, and the tag to ask with next time. With the
    /// tag of the last read, nothing changed answers with no items: the last ones still stand.
    public func search(_ query: Query, tag: String? = nil) async throws -> (items: [SourceItem]?, tag: String?) {
        var parts = URLComponents(url: api.appendingPathComponent("search/issues"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [
            URLQueryItem(name: "q", value: query.text), URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "order", value: "desc"), URLQueryItem(name: "per_page", value: String(limit)),
        ]
        // Only a refused token is unauthorized: a rate limit, an organization that wants a
        // sign-in, or a permission gap answers 403 too, and those pass.
        let reply = try await get(parts.url!, tag: tag, refused: [401])
        if reply.status == 304 { return (nil, tag) }
        guard (200..<300).contains(reply.status) else { throw SourceError.status(reply.status) }
        guard let nodes = Self.json(reply)?["items"] as? [[String: Any]] else { throw SourceError.unreadable("items") }
        return (nodes.compactMap { Self.item($0, role: query.role) }, reply.header("ETag"))
    }

    /// Particular issues and pull requests by `owner/repo#number`, whatever their state now: the
    /// ones found, under the id they were asked by even when their repository was renamed or
    /// moved since, and the ids GitHub no longer has, deleted or never readable with this token.
    /// One this token may not read, or GitHub could not answer for, is in neither list. They are
    /// read at once, in the order asked.
    public func issues(_ ids: [String]) async throws -> (found: [SourceItem], missing: [String]) {
        let answers = try await withThrowingTaskGroup(of: (Int, SourceItem?, Bool).self) { group in
            for (i, id) in ids.enumerated() {
                group.addTask {
                    guard let (owner, repo, number) = Self.split(id) else { return (i, nil, true) }
                    let url = api.appendingPathComponent("repos/\(owner)/\(repo)/issues/\(number)")
                    let reply = try await get(url, refused: [401])
                    switch reply.status {
                    case 404, 410: return (i, nil, true)
                    case 200..<300:
                        guard let json = Self.json(reply), var item = Self.item(json, role: nil) else { throw SourceError.unreadable("issue") }
                        item.id = id
                        return (i, item, false)
                    default: return (i, nil, false)
                    }
                }
            }
            var answers: [(Int, SourceItem?, Bool)] = []
            for try await answer in group { answers.append(answer) }
            return answers.sorted { $0.0 < $1.0 }
        }
        return (answers.compactMap(\.1), answers.filter(\.2).map { ids[$0.0] })
    }

    /// One issue or pull request as a soil item: its title, the repository and kind, when it was
    /// last updated; a to-do until it is closed. Closed without being done, a pull request not
    /// merged or an issue not planned, counts as cancelled.
    static func item(_ json: [String: Any], role: SourceItem.Role?) -> SourceItem? {
        guard let number = (json["number"] as? NSNumber)?.intValue, let repository = Self.repository(json) else { return nil }
        let id = "\(repository)#\(number)"
        let title = (json["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
        let pull = json["pull_request"] as? [String: Any]
        let open = (json["state"] as? String) == "open"
        let done: Bool
        if let pull {
            done = pull["merged_at"] is String
        } else {
            let reason = json["state_reason"] as? String
            done = reason != "not_planned" && reason != "duplicate"
        }
        return SourceItem(
            id: id, title: title, detail: "\(repository) · \(pull == nil ? "Issue" : "Pull request")",
            date: (json["updated_at"] as? String).flatMap(SourceDates.instant), role: role,
            todo: open, cancelled: !open && !done,
            url: (json["html_url"] as? String).flatMap(URL.init(string:))
        )
    }

    /// `owner/repo`, from the repository the item links to.
    static func repository(_ json: [String: Any]) -> String? {
        if let full = (json["repository"] as? [String: Any])?["full_name"] as? String { return full }
        guard let url = (json["repository_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 3, parts[parts.count - 3] == "repos" else { return nil }
        return "\(parts[parts.count - 2])/\(parts[parts.count - 1])"
    }

    /// `octocat/hello-world#12` into its owner, repository and number.
    static func split(_ id: String) -> (owner: String, repo: String, number: Int)? {
        guard let hash = id.lastIndex(of: "#"), let number = Int(id[id.index(after: hash)...]),
              let slash = id[..<hash].firstIndex(of: "/")
        else { return nil }
        let owner = String(id[..<slash]), repo = String(id[id.index(after: slash)..<hash])
        guard [owner, repo].allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." } })
        else { return nil }
        return (owner, repo, number)
    }

    /// Reads one address with the token, asking only for what changed since `tag`. A refused
    /// token is unauthorized; `refused` says which statuses mean that. Any other status is the
    /// caller's to read.
    private func get(_ url: URL, tag: String? = nil, refused: Set<Int> = [401, 403]) async throws -> HTTPReply {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let tag { request.setValue(tag, forHTTPHeaderField: "If-None-Match") }
        let reply = try await http.exchange(request)
        if refused.contains(reply.status) { throw SourceError.unauthorized }
        return reply
    }

    private static func json(_ reply: HTTPReply) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: reply.body) as? [String: Any]
    }
}
