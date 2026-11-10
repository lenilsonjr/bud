import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends one request and hands back the reply. A stand-in replaces it in tests.
public protocol HTTP: Sendable {
    func exchange(_ request: URLRequest) async throws -> HTTPReply
}

extension HTTP {
    /// The body and status alone, for a source that never reads a header.
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let reply = try await exchange(request)
        return (reply.body, reply.status)
    }
}

/// One reply: its body, status and headers.
public struct HTTPReply: Sendable {
    public var body: Data
    public var status: Int
    public var headers: [String: String]

    public init(body: Data, status: Int, headers: [String: String] = [:]) {
        self.body = body
        self.status = status
        self.headers = headers
    }

    /// A header by name, whichever case the server wrote it in.
    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// The real network. A redirect is followed by sending the same request again at the new
/// address, method and body included, which the session would not do for a PROPFIND.
public struct NetworkHTTP: HTTP {
    public init() {}

    public func exchange(_ request: URLRequest) async throws -> HTTPReply {
        var request = request
        for _ in 0..<5 {
            let (data, response) = try await URLSession.shared.data(for: request, delegate: StayPut())
            guard let http = response as? HTTPURLResponse else { return HTTPReply(body: data, status: 0) }
            guard (300..<400).contains(http.statusCode), let location = http.value(forHTTPHeaderField: "Location"),
                  let next = URL(string: location, relativeTo: request.url)
            else {
                var headers: [String: String] = [:]
                for (name, value) in http.allHeaderFields {
                    if let name = name as? String, let value = value as? String { headers[name] = value }
                }
                return HTTPReply(body: data, status: http.statusCode, headers: headers)
            }
            request.url = next.absoluteURL
        }
        throw SourceError.unreadable("redirect")
    }

    private final class StayPut: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}

public enum SourceError: Error, Equatable, Sendable {
    /// The token was refused: 401 or 403.
    case unauthorized
    /// The server answered with something Bud cannot read.
    case unreadable(String)
    case status(Int)
}

/// Mail over JMAP: a session URL and an API token reach one account; Bud reads the newest mail in
/// one mailbox, and asks what changed since the last read before reading again.
public struct JMAPMail: Sendable {
    public struct Mailbox: Hashable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let role: String?
    }

    public let session: URL
    public let token: String
    public let http: HTTP
    /// How many messages the window holds.
    public var limit = 30

    public init(session: URL, token: String, http: HTTP = NetworkHTTP()) {
        self.session = session
        self.token = token
        self.http = http
    }

    /// Where calls go and which account they read, from the session resource.
    public struct Endpoint: Hashable, Sendable {
        public let api: URL
        public let account: String
    }

    public func endpoint() async throws -> Endpoint {
        var request = URLRequest(url: session)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let json = try await object(request)
        guard let api = (json["apiUrl"] as? String).flatMap(URL.init(string:)),
              let primary = json["primaryAccounts"] as? [String: Any],
              let account = primary[Self.mailCapability] as? String
        else { throw SourceError.unreadable("session") }
        return Endpoint(api: api, account: account)
    }

    /// Every mailbox, the Inbox first, then by name.
    public func mailboxes(at endpoint: Endpoint) async throws -> [Mailbox] {
        let result = try await call(endpoint, [["Mailbox/get", ["accountId": endpoint.account, "ids": NSNull(), "properties": ["name", "role"]], "m"]])
        guard let list = result["m"]?["list"] as? [[String: Any]] else { throw SourceError.unreadable("Mailbox/get") }
        let boxes = list.compactMap { box -> Mailbox? in
            guard let id = box["id"] as? String, let name = box["name"] as? String else { return nil }
            return Mailbox(id: id, name: name, role: box["role"] as? String)
        }
        return boxes.sorted { a, b in
            if (a.role == "inbox") != (b.role == "inbox") { return a.role == "inbox" }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// The newest mail in a mailbox, and the state to ask for changes since.
    public func window(at endpoint: Endpoint, mailbox: String) async throws -> (items: [SourceItem], state: String?) {
        let query: [String: Any] = [
            "accountId": endpoint.account,
            "filter": ["inMailbox": mailbox],
            "sort": [["property": "receivedAt", "isAscending": false]],
            "limit": limit,
        ]
        let get: [String: Any] = [
            "accountId": endpoint.account,
            "#ids": ["resultOf": "q", "name": "Email/query", "path": "/ids"],
            "properties": ["subject", "from", "receivedAt", "keywords"],
        ]
        let result = try await call(endpoint, [["Email/query", query, "q"], ["Email/get", get, "g"]])
        guard let list = result["g"]?["list"] as? [[String: Any]] else { throw SourceError.unreadable("Email/get") }
        return (list.compactMap(Self.item), result["g"]?["state"] as? String)
    }

    /// Particular emails by id, wherever they are now: the ones found, and the ids the server no
    /// longer has.
    public func emails(at endpoint: Endpoint, ids: [String]) async throws -> (found: [SourceItem], missing: [String]) {
        guard !ids.isEmpty else { return ([], []) }
        let get: [String: Any] = [
            "accountId": endpoint.account, "ids": ids, "properties": ["subject", "from", "receivedAt", "keywords"],
        ]
        let result = try await call(endpoint, [["Email/get", get, "g"]])
        guard let list = result["g"]?["list"] as? [[String: Any]] else { throw SourceError.unreadable("Email/get") }
        return (list.compactMap(Self.item), result["g"]?["notFound"] as? [String] ?? [])
    }

    /// Whether anything changed since `state`. A server that cannot say counts as a change.
    public func changed(at endpoint: Endpoint, since state: String) async throws -> Bool {
        let result = try await call(endpoint, [["Email/changes", ["accountId": endpoint.account, "sinceState": state], "c"]])
        guard let changes = result["c"] else { return true }
        if changes["type"] != nil { return true }
        let count = ["created", "updated", "destroyed"].reduce(0) { $0 + ((changes[$1] as? [Any])?.count ?? 0) }
        return count > 0 || (changes["newState"] as? String) != state
    }

    /// One email as a soil item: its subject, the sender, unread unless seen, a to-do when flagged.
    static func item(_ email: [String: Any]) -> SourceItem? {
        guard let id = email["id"] as? String else { return nil }
        let subject = (email["subject"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "No subject"
        let sender = (email["from"] as? [[String: Any]])?.first
        let name = (sender?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? sender?["email"] as? String
        let keywords = email["keywords"] as? [String: Any] ?? [:]
        let date = (email["receivedAt"] as? String).flatMap(SourceDates.instant)
        return SourceItem(
            id: id, title: subject, detail: name, date: date,
            unread: keywords["$seen"] == nil, todo: keywords["$flagged"] != nil
        )
    }

    static let mailCapability = "urn:ietf:params:jmap:mail"

    /// Runs method calls in one request and hands back each result by its tag. A method error
    /// comes back as its result with a `type`.
    private func call(_ endpoint: Endpoint, _ calls: [[Any]]) async throws -> [String: [String: Any]] {
        var request = URLRequest(url: endpoint.api)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "using": ["urn:ietf:params:jmap:core", Self.mailCapability],
            "methodCalls": calls,
        ])
        let json = try await object(request)
        guard let responses = json["methodResponses"] as? [[Any]] else { throw SourceError.unreadable("methodResponses") }
        var byTag: [String: [String: Any]] = [:]
        for response in responses where response.count == 3 {
            guard let result = response[1] as? [String: Any], let tag = response[2] as? String else { continue }
            byTag[tag] = result
        }
        return byTag
    }

    private func object(_ request: URLRequest) async throws -> [String: Any] {
        let (data, status) = try await http.send(request)
        if status == 401 || status == 403 { throw SourceError.unauthorized }
        guard (200..<300).contains(status) else { throw SourceError.status(status) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SourceError.unreadable("body")
        }
        return json
    }
}
