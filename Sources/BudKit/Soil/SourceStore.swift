import Foundation
#if canImport(Combine)
import Combine
#endif

/// What Bud keeps about a connected account besides its token.
public struct SourceConfig: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: SourceKind
    public var name: String
    /// Mail: the JMAP session resource.
    public var session: URL?
    /// Mail: the mailbox the soil shows.
    public var mailbox: String?

    public init(id: String = UUID().uuidString, kind: SourceKind, name: String, session: URL? = nil, mailbox: String? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.session = session
        self.mailbox = mailbox
    }
}

/// The accounts this device reads below the soil. It keeps their settings, reads each one whose
/// token this device holds, and shows the rest locked. Nothing it reads is written to the vault.
@MainActor
public final class SourceStore: ObservableObject {
    public static let shared = SourceStore(defaults: .standard, tokens: SourceStore.deviceTokens, http: NetworkHTTP())

    @Published public private(set) var configs: [SourceConfig]
    /// One per config, in the same order, with the items last read.
    @Published public private(set) var accounts: [SourceAccount] = []
    /// Why an account could not be read, by its id.
    @Published public private(set) var problems: [String: String] = [:]

    private let defaults: UserDefaults
    private let tokens: TokenStore
    private let http: HTTP
    /// What each mail account last read, so the next read can ask what changed first.
    private var seen: [String: (endpoint: JMAPMail.Endpoint, state: String?)] = [:]
    private var items: [String: [SourceItem]] = [:]
    private var polling: Task<Void, Never>?

    static let configsKey = "sources"
    /// How often the soil reads its sources while the app runs.
    public static let interval: Duration = .seconds(120)

    nonisolated static var deviceTokens: TokenStore {
        #if canImport(Security)
        return KeychainTokens()
        #else
        return MemoryTokens()
        #endif
    }

    public init(defaults: UserDefaults, tokens: TokenStore, http: HTTP) {
        self.defaults = defaults
        self.tokens = tokens
        self.http = http
        let saved = defaults.data(forKey: Self.configsKey).flatMap { try? JSONDecoder().decode([SourceConfig].self, from: $0) }
        configs = saved ?? []
        publish()
    }

    // MARK: connecting mail

    /// Checks a session and token and hands back the mailboxes to choose from, the Inbox first.
    public func mailboxes(session: URL, token: String) async throws -> [JMAPMail.Mailbox] {
        let mail = JMAPMail(session: session, token: token, http: http)
        return try await mail.mailboxes(at: try await mail.endpoint())
    }

    /// Adds a mail account that reads one mailbox, keeps its token on this device, and reads it.
    @discardableResult
    public func connectMail(name: String, session: URL, token: String, mailbox: String) async -> SourceConfig {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = SourceConfig(kind: .mail, name: trimmed.isEmpty ? SourceKind.mail.name : trimmed, session: session, mailbox: mailbox)
        tokens.set(token, for: config.id)
        configs.append(config)
        save()
        await read(config)
        return config
    }

    /// Signs this device in to an account another device connected.
    public func signIn(_ id: String, token: String) async {
        guard let config = configs.first(where: { $0.id == id }) else { return }
        tokens.set(token, for: id)
        await read(config)
    }

    /// Forgets an account and its token on this device.
    public func disconnect(_ id: String) {
        tokens.set(nil, for: id)
        configs.removeAll { $0.id == id }
        items[id] = nil
        seen[id] = nil
        problems[id] = nil
        save()
        publish()
    }

    // MARK: reading

    /// Reads every account this device holds a token for.
    public func refresh() async {
        for config in configs { await read(config) }
    }

    /// Reads now and then every `interval` until `stop`.
    public func start() {
        guard polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    public func stop() {
        polling?.cancel()
        polling = nil
    }

    private func read(_ config: SourceConfig) async {
        guard let token = tokens.token(for: config.id) else { return publish() }
        do {
            switch config.kind {
            case .mail:
                guard let session = config.session, let mailbox = config.mailbox else { return }
                let mail = JMAPMail(session: session, token: token, http: http)
                let endpoint: JMAPMail.Endpoint
                if let known = seen[config.id]?.endpoint { endpoint = known } else { endpoint = try await mail.endpoint() }
                if let state = seen[config.id]?.state, !(try await mail.changed(at: endpoint, since: state)) { break }
                let window = try await mail.window(at: endpoint, mailbox: mailbox)
                items[config.id] = window.items
                seen[config.id] = (endpoint, window.state)
            case .calendar, .github, .linear:
                break
            }
            problems[config.id] = nil
        } catch SourceError.unauthorized {
            problems[config.id] = "The token was refused. Sign in again on this device."
            seen[config.id] = nil
        } catch {
            problems[config.id] = "Couldn't reach \(config.name). Bud will try again."
        }
        publish()
    }

    private func publish() {
        accounts = configs.map { config in
            SourceAccount(
                id: config.id, kind: config.kind, name: config.name,
                locked: tokens.token(for: config.id) == nil, items: items[config.id] ?? []
            )
        }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(configs), forKey: Self.configsKey)
    }
}
