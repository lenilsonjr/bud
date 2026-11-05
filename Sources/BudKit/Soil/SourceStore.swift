import Foundation
#if canImport(Combine)
import Combine
#endif

/// What Bud keeps about a connected account besides its token.
public struct SourceConfig: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: SourceKind
    public var name: String
    /// Mail: the JMAP session resource. Calendar: the CalDAV server.
    public var session: URL?
    /// Mail: the mailbox the soil shows.
    public var mailbox: String?
    /// Calendar: the user name and the calendar the soil shows.
    public var user: String?
    public var calendar: URL?

    public init(
        id: String = UUID().uuidString, kind: SourceKind, name: String, session: URL? = nil, mailbox: String? = nil,
        user: String? = nil, calendar: URL? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.session = session
        self.mailbox = mailbox
        self.user = user
        self.calendar = calendar
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
    /// Now; a test moves it.
    var clock: () -> Date = Date.init
    /// What each mail account last read, so the next read can ask what changed first.
    private var seen: [String: (endpoint: JMAPMail.Endpoint, state: String?)] = [:]
    /// Each calendar's sync token and when its window was last read; the window moves with the
    /// clock, so it is read again after an hour even when the token stands still.
    private var calendarSeen: [String: (token: String?, at: Date)] = [:]
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

    // MARK: connecting a calendar

    /// Checks a server, user name and app password and hands back the calendars to choose from.
    public func calendars(server: URL, user: String, password: String) async throws -> [CalDAV.Calendar] {
        try await CalDAV(server: server, user: user, password: password, http: http).calendars()
    }

    /// Adds a calendar account that reads one calendar, keeps its password on this device, and reads it.
    @discardableResult
    public func connectCalendar(name: String, server: URL, user: String, password: String, calendar: URL) async -> SourceConfig {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = SourceConfig(
            kind: .calendar, name: trimmed.isEmpty ? SourceKind.calendar.name : trimmed, session: server, user: user, calendar: calendar)
        tokens.set(password, for: config.id)
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
        calendarSeen[id] = nil
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
            case .calendar:
                guard let server = config.session, let user = config.user, let calendar = config.calendar else { return }
                let cal = CalDAV(server: server, user: user, password: token, http: http)
                let now = clock()
                let syncToken = try await cal.syncToken(of: calendar)
                if let last = calendarSeen[config.id], let syncToken, last.token == syncToken, now.timeIntervalSince(last.at) < 3600 { break }
                items[config.id] = try await cal.window(of: calendar, now: now)
                calendarSeen[config.id] = (syncToken, now)
            case .github, .linear:
                break
            }
            problems[config.id] = nil
            readAt[config.id] = clock()
        } catch SourceError.unauthorized {
            problems[config.id] = "The token was refused. Sign in again on this device."
            seen[config.id] = nil
            calendarSeen[config.id] = nil
        } catch {
            problems[config.id] = "Couldn't reach \(config.name). Bud will try again."
        }
        publish()
    }

    private func publish() {
        accounts = configs.map { config in
            SourceAccount(
                id: config.id, kind: config.kind, name: config.name,
                locked: tokens.token(for: config.id) == nil, items: (items[config.id] ?? []).filter { !$0.cancelled }
            )
        }
        refreshed += 1
    }

    // MARK: keeping planted buds live

    /// Counts the reads, so a store can keep its planted buds live after each one.
    @Published public private(set) var refreshed = 0
    /// When each account was last read without a problem.
    public private(set) var readAt: [String: Date] = [:]

    /// What this device can say now about planted items, by `from` key: seen, gone, or left out
    /// when it cannot tell: no token here, a problem reading, or an event beyond the window.
    /// `when` is the bud's day, which says whether a calendar event should be in the window.
    public func sightings(for planted: [(from: String, when: Date?)]) async -> [String: Sighting] {
        var found: [String: Sighting] = [:]
        let now = clock()
        for config in configs where problems[config.id] == nil {
            guard let token = tokens.token(for: config.id), readAt[config.id] != nil else { continue }
            let mine = planted.filter { SourceRowText.origin($0.from).kind == config.kind && found[$0.from] == nil }
            guard !mine.isEmpty else { continue }
            let window = Dictionary((items[config.id] ?? []).map { (config.kind.key($0.id), $0) }, uniquingKeysWith: { a, _ in a })
            var asked: [String] = []
            for item in mine {
                if let seen = window[item.from] {
                    found[item.from] = .seen(seen)
                } else if config.kind == .calendar, let when = item.when,
                          // A bud keeps the day only, so today's events may already have left the window.
                          let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)),
                          when >= tomorrow, when < now.addingTimeInterval(13 * 86_400) {
                    found[item.from] = .gone
                } else if config.kind == .mail {
                    asked.append(SourceRowText.origin(item.from).id)
                }
            }
            guard config.kind == .mail, !asked.isEmpty, let session = config.session,
                  let endpoint = seen[config.id]?.endpoint else { continue }
            do {
                let answer = try await JMAPMail(session: session, token: token, http: http).emails(at: endpoint, ids: asked)
                for item in answer.found { found[config.kind.key(item.id)] = .seen(item) }
                // Another mail account may still hold it; only the last one asked says gone.
                if configs.last(where: { $0.kind == .mail }) == config {
                    for id in answer.missing { found[config.kind.key(id)] = .gone }
                }
            } catch {
                continue
            }
        }
        return found
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(configs), forKey: Self.configsKey)
    }
}
