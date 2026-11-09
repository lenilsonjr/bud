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
    /// Calendar: the user name, and the calendars the soil shows. `calendar` is the first of them,
    /// kept for a device on a build that reads one.
    public var user: String?
    public var calendar: URL?
    public var calendars: [CalendarPick]?
    /// When it was connected, which keeps the roots in that order on every device.
    public var added: Date?

    /// One calendar of an account, with the name its server gave it.
    public struct CalendarPick: Codable, Hashable, Sendable {
        public var url: URL
        public var name: String

        public init(url: URL, name: String) {
            self.url = url
            self.name = name
        }
    }

    public init(
        id: String = UUID().uuidString, kind: SourceKind, name: String, session: URL? = nil, mailbox: String? = nil,
        user: String? = nil, calendars: [CalendarPick] = []
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.session = session
        self.mailbox = mailbox
        self.user = user
        calendar = calendars.first?.url
        self.calendars = calendars.isEmpty ? nil : calendars
        added = Date()
    }

    /// The calendars the account reads: the list, or the one an older build saved.
    public var calendarPicks: [CalendarPick] {
        calendars ?? calendar.map { [CalendarPick(url: $0, name: "")] } ?? []
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
    /// Each calendar's sync token and when its window was last read, by account and calendar; the
    /// window moves with the clock, so it is read again after an hour even when the token stands
    /// still. The items of each calendar are kept apart, so one that has not moved is not read again.
    private var calendarSeen: [String: (token: String?, at: Date)] = [:]
    private var calendarItems: [String: [SourceItem]] = [:]
    /// Each Linear account's newest update and when it was last read in full; read again after an
    /// hour anyway, since an issue taken off you no longer counts as an update to your issues.
    private var linearSeen: [String: (updated: Date?, at: Date)] = [:]
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
        if let known = defaults.string(forKey: Self.deviceKey) {
            device = known
        } else {
            device = UUID().uuidString
            defaults.set(device, forKey: Self.deviceKey)
        }
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
        configs.append(config)
        save()
        await share(config)
        keep(token, for: config)
        publish()
        await read(config)
        return config
    }

    /// Keeps a token on this device, or says it could not.
    private func keep(_ token: String, for config: SourceConfig) {
        if !tokens.set(token, for: config.id) { problems[config.id] = "Couldn't keep the token on this device." }
    }

    // MARK: connecting a calendar

    /// Checks a server, user name and app password and hands back the calendars to choose from.
    public func calendars(server: URL, user: String, password: String) async throws -> [CalDAV.Calendar] {
        try await CalDAV(server: server, user: user, password: password, http: http).calendars()
    }

    /// Adds a calendar account that reads the calendars picked, keeps its password on this device,
    /// and reads it.
    @discardableResult
    public func connectCalendar(name: String, server: URL, user: String, password: String, calendars: [CalDAV.Calendar]) async -> SourceConfig {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = SourceConfig(
            kind: .calendar, name: trimmed.isEmpty ? SourceKind.calendar.name : trimmed, session: server, user: user,
            calendars: calendars.map { SourceConfig.CalendarPick(url: $0.url, name: $0.name) })
        configs.append(config)
        save()
        await share(config)
        keep(password, for: config)
        publish()
        await read(config)
        return config
    }

    /// Adds a calendar account that reads one calendar.
    @discardableResult
    public func connectCalendar(name: String, server: URL, user: String, password: String, calendar: URL) async -> SourceConfig {
        await connectCalendar(name: name, server: server, user: user, password: password, calendars: [CalDAV.Calendar(url: calendar, name: "")])
    }

    /// The calendars a connected account could read, found with the password this device keeps.
    public func calendars(of id: String) async throws -> [CalDAV.Calendar] {
        guard let config = configs.first(where: { $0.id == id }), let server = config.session, let user = config.user,
              let password = tokens.token(for: id)
        else { throw SourceError.unauthorized }
        return try await calendars(server: server, user: user, password: password)
    }

    /// The calendars a connected account reads.
    public func calendarPicks(of id: String) -> [SourceConfig.CalendarPick] {
        configs.first { $0.id == id }?.calendarPicks ?? []
    }

    /// Changes which calendars an account reads, and reads it again.
    public func setCalendars(_ id: String, _ calendars: [CalDAV.Calendar]) async {
        guard let index = configs.firstIndex(where: { $0.id == id }) else { return }
        configs[index].calendars = calendars.map { SourceConfig.CalendarPick(url: $0.url, name: $0.name) }
        configs[index].calendar = calendars.first?.url
        save()
        await share(configs[index])
        forgetCalendars(of: id)
        await read(configs[index])
    }

    private func forgetCalendars(of id: String) {
        for key in calendarSeen.keys where key == id || key.hasPrefix("\(id)#") { calendarSeen[key] = nil }
        for key in calendarItems.keys where key.hasPrefix("\(id)#") { calendarItems[key] = nil }
    }

    // MARK: connecting Linear

    /// Checks a personal API key and hands back the name of the workspace it reads.
    public func linearWorkspace(token: String) async throws -> String {
        try await LinearIssues(token: token, http: http).workspace()
    }

    /// Adds a Linear account that reads the open issues assigned to you, keeps its key on this
    /// device, and reads it.
    @discardableResult
    public func connectLinear(name: String, token: String) async -> SourceConfig {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = SourceConfig(kind: .linear, name: trimmed.isEmpty ? SourceKind.linear.name : trimmed)
        configs.append(config)
        save()
        await share(config)
        keep(token, for: config)
        publish()
        await read(config)
        return config
    }

    /// Signs this device in to an account another device connected.
    public func signIn(_ id: String, token: String) async {
        guard let config = configs.first(where: { $0.id == id }) else { return }
        keep(token, for: config)
        publish()
        await read(config)
    }

    /// Forgets an account and its token on this device.
    public func disconnect(_ id: String) {
        tokens.set(nil, for: id)
        configs.removeAll { $0.id == id }
        items[id] = nil
        seen[id] = nil
        forgetCalendars(of: id)
        linearSeen[id] = nil
        problems[id] = nil
        removed.insert(id)
        waiting.remove(id)
        save()
        publish()
        if let vault {
            Task {
                try? await vault.setShared(.sources, id, nil)
                try? await vault.setShared(.leases, id, nil)
            }
        }
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
                guard let server = config.session, let user = config.user else { return }
                let picks = config.calendarPicks
                guard !picks.isEmpty else { return }
                let cal = CalDAV(server: server, user: user, password: token, http: http)
                let now = clock()
                var all: [SourceItem] = []
                for pick in picks {
                    let key = "\(config.id)#\(pick.url.absoluteString)"
                    let syncToken = try await cal.syncToken(of: pick.url)
                    if let last = calendarSeen[key], let syncToken, last.token == syncToken, now.timeIntervalSince(last.at) < 3600 {
                        all += calendarItems[key] ?? []
                        continue
                    }
                    var read = try await cal.window(of: pick.url, now: now)
                    // With several calendars, an item says which one it came from.
                    if picks.count > 1, !pick.name.isEmpty {
                        read = read.map { item in
                            var item = item
                            item.detail = [pick.name, item.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                            return item
                        }
                    }
                    calendarItems[key] = read
                    calendarSeen[key] = (syncToken, now)
                    all += read
                }
                if picks.count > 1 { all.sort { ($0.date ?? .distantFuture, $0.id) < ($1.date ?? .distantFuture, $1.id) } }
                items[config.id] = all
            case .linear:
                let linear = LinearIssues(token: token, http: http)
                let now = clock()
                var newest = linearSeen[config.id]?.updated
                if let last = linearSeen[config.id], let since = last.updated, now.timeIntervalSince(last.at) < 3600 {
                    guard let update = try await linear.changed(since: since) else { break }
                    newest = update
                }
                let window = try await linear.window()
                items[config.id] = window.items
                // The later of the two: a closed issue's update is newer than any open one's.
                let updated = [newest, window.updated].compactMap { $0 }.max()
                linearSeen[config.id] = (updated, now)
            case .github:
                break
            }
            problems[config.id] = nil
            readAt[config.id] = clock()
        } catch SourceError.unauthorized {
            problems[config.id] = "The token was refused. Sign in again on this device."
            seen[config.id] = nil
            forgetCalendars(of: config.id)
            linearSeen[config.id] = nil
        } catch {
            problems[config.id] = "Couldn't reach \(config.name). Bud will try again."
        }
        publish()
    }

    private func publish() {
        accounts = configs.map { config in
            SourceAccount(
                id: config.id, kind: config.kind, name: config.name,
                locked: tokens.token(for: config.id) == nil, items: (items[config.id] ?? []).filter { !$0.cancelled },
                calendars: config.calendarPicks.count
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
        for kind in SourceKind.allCases {
            let accounts = configs.filter { $0.kind == kind }
            let readable = accounts.filter { problems[$0.id] == nil && readAt[$0.id] != nil && tokens.token(for: $0.id) != nil }
            let mine = planted.filter { SourceRowText.origin($0.from).kind == kind }
            guard !readable.isEmpty, !mine.isEmpty else { continue }
            // Only when every account of this kind was read can an item missing from all of them be gone.
            let everyone = readable.count == accounts.count
            for config in readable {
                for item in items[config.id] ?? [] where found[kind.key(item.id)] == nil {
                    found[kind.key(item.id)] = .seen(item)
                }
            }
            var left = mine.filter { found[$0.from] == nil }
            switch kind {
            case .calendar:
                // A bud keeps the day only, so today's events may already have left the window.
                guard everyone, let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) else { break }
                for item in left {
                    if let when = item.when, when >= tomorrow, when < now.addingTimeInterval(13 * 86_400) { found[item.from] = .gone }
                }
            case .mail:
                var missingEverywhere = Set(left.map { SourceRowText.origin($0.from).id })
                var answered = 0
                for config in readable where !left.isEmpty {
                    guard let token = tokens.token(for: config.id), let session = config.session,
                          let endpoint = seen[config.id]?.endpoint else { continue }
                    let ids = left.map { SourceRowText.origin($0.from).id }
                    guard let answer = try? await JMAPMail(session: session, token: token, http: http).emails(at: endpoint, ids: ids) else { continue }
                    answered += 1
                    for item in answer.found {
                        found[kind.key(item.id)] = .seen(item)
                        missingEverywhere.remove(item.id)
                    }
                    left = left.filter { found[$0.from] == nil }
                }
                if everyone, answered == readable.count {
                    for id in missingEverywhere { found[kind.key(id)] = .gone }
                }
            case .linear:
                // A closed issue leaves the window but is still there to read.
                var missingEverywhere = Set(left.map { SourceRowText.origin($0.from).id })
                var answered = 0
                for config in readable where !left.isEmpty {
                    guard let token = tokens.token(for: config.id) else { continue }
                    let ids = left.map { SourceRowText.origin($0.from).id }
                    guard let answer = try? await LinearIssues(token: token, http: http).issues(ids) else { continue }
                    answered += 1
                    for item in answer.found {
                        found[kind.key(item.id)] = .seen(item)
                        missingEverywhere.remove(item.id)
                    }
                    left = left.filter { found[$0.from] == nil }
                }
                if everyone, answered == readable.count {
                    for id in missingEverywhere { found[kind.key(id)] = .gone }
                }
            case .github:
                break
            }
        }
        return found.filter { key, _ in planted.contains { $0.from == key } }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(configs), forKey: Self.configsKey)
    }

    // MARK: the list and the leases in the vault

    /// Which device keeps an account's planted buds live, until when, and when it last synced.
    public struct Lease: Codable, Hashable, Sendable {
        public var holder: String
        public var name: String
        public var until: Date
        public var synced: Date
    }

    private var vault: Vault?
    public private(set) var leases: [String: Lease] = [:]
    /// What this device is called on a source row: "Mac", "iPad".
    public var deviceName = "This device"
    /// This install, as a lease names it.
    public let device: String
    nonisolated static let deviceKey = "sourceDevice"
    static let movedKey = "sourcesMovedToVault"
    /// How long a lease runs without renewal: a few reads, so a device that went away hands over soon.
    public static let leaseLength: TimeInterval = 600

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Keeps the list of sources in the vault from now on, so every device sees it. A list this
    /// device kept before moves there the first time.
    public func use(_ vault: Vault) async {
        self.vault = vault
        await reloadShared()
    }

    /// Reads the list and the leases again, after a sync brought someone else's changes.
    public func reloadShared() async {
        guard let vault else { return }
        // What was here before the read: an account connected while this reads is kept.
        let known = Set(configs.map(\.id))
        guard var stored = try? await vault.shared(.sources) else { return }
        // Once only, the accounts this device kept itself join the vault's list; after that an
        // account missing from the vault was disconnected somewhere. Also the ones connected
        // before the vault was attached.
        let unshared = defaults.bool(forKey: Self.movedKey) ? configs.filter { waiting.contains($0.id) } : configs
        var moved = true
        for config in unshared where stored[config.id] == nil && !removed.contains(config.id) {
            guard let text = await share(config) else { moved = false; continue }
            waiting.remove(config.id)
            stored[config.id] = text
        }
        if moved { defaults.set(true, forKey: Self.movedKey) }
        var list = stored.filter { !removed.contains($0.key) }.values
            .compactMap { try? Self.decoder.decode(SourceConfig.self, from: Data($0.utf8)) }
        let ids = Set(list.map(\.id))
        // Kept too: one connected while this read, and one whose share has not landed yet.
        list += configs.filter {
            (!known.contains($0.id) || waiting.contains($0.id) || sharing.contains($0.id))
                && !ids.contains($0.id) && !removed.contains($0.id)
        }
        list.sort { ($0.added ?? .distantPast, $0.id) < ($1.added ?? .distantPast, $1.id) }
        let leased = (try? await vault.shared(.leases)) ?? [:]
        leases = leased.compactMapValues { try? Self.decoder.decode(Lease.self, from: Data($0.utf8)) }
        if list != configs {
            configs = list
            save()
            publish()
        }
    }

    /// Puts an account's settings in the vault and hands back what was written; nil when it could
    /// not, or before a vault is attached, when it waits for one.
    @discardableResult
    private func share(_ config: SourceConfig) async -> String? {
        guard let vault, let data = try? Self.encoder.encode(config) else {
            waiting.insert(config.id)
            return nil
        }
        let text = String(decoding: data, as: UTF8.self)
        sharing.insert(config.id)
        defer { sharing.remove(config.id) }
        do {
            try await vault.setShared(.sources, config.id, text)
            // Disconnected while it was being written: the removal may have landed first.
            if removed.contains(config.id) {
                try? await vault.setShared(.sources, config.id, nil)
                return nil
            }
            return text
        } catch {
            waiting.insert(config.id)
            return nil
        }
    }

    /// Accounts whose settings are being written to the vault.
    private var sharing: Set<String> = []
    /// Accounts connected here and not yet in the vault.
    private var waiting: Set<String> = []
    /// Accounts disconnected here, which a read of the vault before the removal lands must not bring back.
    private var removed: Set<String> = []

    /// Takes or renews the lease of each account this device reads, unless another device holds
    /// one that still runs, and says which kinds this device keeps live now.
    public func holdLeases() async -> Set<SourceKind> {
        let now = clock()
        if let vault {
            let leased = (try? await vault.shared(.leases)) ?? [:]
            leases = leased.compactMapValues { try? Self.decoder.decode(Lease.self, from: Data($0.utf8)) }
        }
        // A kind is kept live here when this device holds the lease of any of its accounts; two
        // devices holding two accounts of one kind write the same values, which merge as one.
        var held = Set<SourceKind>()
        for config in configs where problems[config.id] == nil && readAt[config.id] != nil && tokens.token(for: config.id) != nil {
            if let lease = leases[config.id], lease.holder != device, lease.until > now { continue }
            held.insert(config.kind)
            // Renewed only when half run out: each write is history the vault keeps.
            if let lease = leases[config.id], lease.holder == device, lease.until.timeIntervalSince(now) > Self.leaseLength / 2 {
                continue
            }
            let lease = Lease(holder: device, name: deviceName, until: now.addingTimeInterval(Self.leaseLength), synced: now)
            leases[config.id] = lease
            if let vault, let data = try? Self.encoder.encode(lease) {
                try? await vault.setShared(.leases, config.id, String(decoding: data, as: UTF8.self))
            }
        }
        return held
    }

    /// The latest sync of any account of this kind, and the device that ran it.
    public func lastSync(of kind: SourceKind) -> Lease? {
        configs.filter { $0.kind == kind }.compactMap { leases[$0.id] }.max { $0.synced < $1.synced }
    }
}
