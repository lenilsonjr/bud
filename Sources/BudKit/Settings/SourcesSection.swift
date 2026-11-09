#if canImport(SwiftUI) && !os(tvOS)
import SwiftUI

/// The SOURCES section of Settings: each connected account with what it reads, a lock where this
/// device has no token, and Connect mail.
struct SourcesSection: View {
    @ObservedObject var sources: SourceStore
    let present: (Modal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SOURCES")
                .textRole(.eyebrow)
                .foregroundStyle(Theme.text3)
            ForEach(sources.accounts) { account in
                row(account)
            }
            HStack(spacing: 8) {
                Button { present(.connectMail(account: nil)) } label: {
                    BudButtonLabel(title: "Connect mail…", systemImage: "envelope")
                }
                Button { present(.connectCalendar) } label: {
                    BudButtonLabel(title: "Connect calendar…", systemImage: "calendar")
                }
                Button { present(.connectLinear) } label: {
                    BudButtonLabel(title: "Connect Linear…", systemImage: SoilView.symbol(.linear))
                }
            }
            .buttonStyle(.budSecondary)
            Text(SourcesText.caption)
                .textRole(.caption)
                .foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ account: SourceAccount) -> some View {
        HStack(spacing: 8) {
            Image(systemName: SoilView.symbol(account.kind))
                .foregroundStyle(Theme.text2)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name).textRole(.label)
                Text(sources.problems[account.id] ?? SourcesText.status(account))
                    .textRole(.caption)
                    .foregroundStyle(sources.problems[account.id] == nil ? Theme.text3 : Theme.rose)
            }
            Spacer()
            if account.locked {
                Button("Sign in") { present(.connectMail(account: account.id)) }
                    .buttonStyle(.budGhost)
            }
            Button("Disconnect") { sources.disconnect(account.id) }
                .buttonStyle(.budGhost)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("source-\(account.id)")
    }
}

/// Connect mail over JMAP: the session address and an API token, then the mailbox the soil shows.
/// With an account, only the token: signing this device in to an account another one connected.
struct ConnectMailSheet: View {
    @ObservedObject var sources: SourceStore
    let account: String?
    let close: () -> Void

    @State private var name = ""
    @State private var session = SourcesText.defaultSession
    @State private var token = ""
    @State private var boxes: [JMAPMail.Mailbox] = []
    @State private var picked: String?
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        DialogBody(title: account == nil ? "Connect mail" : "Sign in on this device", text: SourcesText.connectBody) {
            VStack(alignment: .leading, spacing: 10) {
                if boxes.isEmpty {
                    if account == nil {
                        TextField("Name, as in Work mail", text: $name)
                        TextField("Session address", text: $session)
                            .textRole(.mono)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                            .autocorrectionDisabled()
                    }
                    SecureField(account == nil ? "API token" : "Token or app password", text: $token)
                        .accessibilityIdentifier("source-token")
                } else {
                    Text("Show this mailbox below the soil").textRole(.label).foregroundStyle(Theme.text2)
                    ForEach(boxes) { box in
                        DialogChoice(on: picked == box.id, title: box.name, caption: box.role == "inbox" ? "Your Inbox" : "") {
                            picked = box.id
                        }
                    }
                }
                if let problem {
                    Text(problem).textRole(.caption).foregroundStyle(Theme.rose)
                }
            }
            .textFieldStyle(.roundedBorder)
        } actions: {
            Button(action: close) { BudButtonLabel(title: "Cancel") }
                .buttonStyle(.budSecondary)
                .keyboardShortcut(.cancelAction)
            Button(action: next) { BudButtonLabel(title: busy ? "Checking…" : nextTitle) }
                .buttonStyle(.budPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(busy || token.isEmpty || (boxes.isEmpty == false && picked == nil))
        }
    }

    private var nextTitle: String {
        if account != nil { return "Sign in" }
        return boxes.isEmpty ? "Continue" : "Connect"
    }

    private func next() {
        if let account {
            Task {
                await sources.signIn(account, token: token)
                close()
            }
            return
        }
        guard let url = URL(string: session.trimmingCharacters(in: .whitespaces)), url.scheme == "https" else {
            problem = SourcesText.badAddress
            return
        }
        if let picked {
            Task {
                await sources.connectMail(name: name, session: url, token: token, mailbox: picked)
                close()
            }
            return
        }
        busy = true
        problem = nil
        Task {
            do {
                let found = try await sources.mailboxes(session: url, token: token)
                boxes = found
                picked = found.first?.id
            } catch {
                problem = SourcesText.problem(error)
            }
            busy = false
        }
    }
}
/// Connect a calendar over CalDAV: the server, a user name and an app password, then the calendar
/// the soil shows.
struct ConnectCalendarSheet: View {
    @ObservedObject var sources: SourceStore
    let close: () -> Void

    @State private var server = SourcesText.servers[0].url
    @State private var other = ""
    @State private var name = ""
    @State private var user = ""
    @State private var password = ""
    @State private var calendars: [CalDAV.Calendar] = []
    @State private var picked: URL?
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        DialogBody(title: "Connect a calendar", text: SourcesText.calendarBody) {
            VStack(alignment: .leading, spacing: 10) {
                if calendars.isEmpty {
                    ForEach(SourcesText.servers, id: \.url) { choice in
                        DialogChoice(on: server == choice.url, title: choice.name, caption: choice.caption) { server = choice.url }
                    }
                    DialogChoice(on: server.isEmpty, title: "Another server", caption: "Any CalDAV address") { server = "" }
                    if server.isEmpty {
                        TextField("https://", text: $other)
                            .textRole(.mono)
                            .autocorrectionDisabled()
                    }
                    TextField("Name, as in Home", text: $name)
                    TextField("User name or email", text: $user)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    SecureField("App password", text: $password)
                } else {
                    Text("Show this calendar below the soil").textRole(.label).foregroundStyle(Theme.text2)
                    ForEach(calendars) { calendar in
                        DialogChoice(on: picked == calendar.url, title: calendar.name, caption: "") { picked = calendar.url }
                    }
                }
                if let problem {
                    Text(problem).textRole(.caption).foregroundStyle(Theme.rose)
                }
            }
            .textFieldStyle(.roundedBorder)
        } actions: {
            Button(action: close) { BudButtonLabel(title: "Cancel") }
                .buttonStyle(.budSecondary)
                .keyboardShortcut(.cancelAction)
            Button(action: next) { BudButtonLabel(title: busy ? "Checking…" : (calendars.isEmpty ? "Continue" : "Connect")) }
                .buttonStyle(.budPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(busy || user.isEmpty || password.isEmpty || (!calendars.isEmpty && picked == nil))
        }
    }

    private func next() {
        let address = (server.isEmpty ? other : server).trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: address), url.scheme == "https" else {
            problem = SourcesText.badAddress
            return
        }
        if let picked {
            Task {
                await sources.connectCalendar(name: name, server: url, user: user, password: password, calendar: picked)
                close()
            }
            return
        }
        busy = true
        problem = nil
        Task {
            do {
                let found = try await sources.calendars(server: url, user: user, password: password)
                calendars = found
                picked = found.first?.url
                if found.isEmpty { problem = SourcesText.noCalendars }
            } catch {
                problem = SourcesText.problem(error)
            }
            busy = false
        }
    }
}

/// Connect Linear with a personal API key; the soil shows the open issues assigned to you.
struct ConnectLinearSheet: View {
    @ObservedObject var sources: SourceStore
    let close: () -> Void

    @State private var name = ""
    @State private var token = ""
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        DialogBody(title: "Connect Linear", text: SourcesText.linearBody) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Name, as in Work", text: $name)
                SecureField("Personal API key", text: $token)
                    .accessibilityIdentifier("source-token")
                if let problem {
                    Text(problem).textRole(.caption).foregroundStyle(Theme.rose)
                }
            }
            .textFieldStyle(.roundedBorder)
        } actions: {
            Button(action: close) { BudButtonLabel(title: "Cancel") }
                .buttonStyle(.budSecondary)
                .keyboardShortcut(.cancelAction)
            Button(action: connect) { BudButtonLabel(title: busy ? "Checking…" : "Connect") }
                .buttonStyle(.budPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(busy || token.isEmpty)
        }
    }

    private func connect() {
        busy = true
        problem = nil
        let key = token.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let workspace = try await sources.linearWorkspace(token: key)
                await sources.connectLinear(name: name.isEmpty ? workspace : name, token: key)
                close()
            } catch {
                problem = SourcesText.problem(error)
            }
            busy = false
        }
    }
}
#endif

/// The words of Settings › Sources, kept pure so a test reads them on any platform.
public enum SourcesText {
    public static let caption = "Sources show below the soil on the canvas. Nothing is saved until you plant it. Tokens stay on this device."
    public static let connectBody = "Bud reads your newest mail over JMAP. Make an API token with read access to mail in your provider's settings."
    public static let defaultSession = "https://api.fastmail.com/jmap/session"
    public static let badAddress = "The address starts with https://."
    public static let calendarBody = "Bud reads the next 14 days of one calendar over CalDAV. Use an app password, not your account password."
    public static let linearBody = "Bud shows the open issues assigned to you. Make a personal API key in Linear under Settings › Security & access."
    public static let noCalendars = "No calendar with events was found there."
    /// The servers most people use, ready to pick.
    public static let servers: [(name: String, caption: String, url: String)] = [
        ("iCloud", "Make an app password at account.apple.com", "https://caldav.icloud.com/"),
        ("Fastmail", "Make an app password in Settings › Privacy & Security", "https://caldav.fastmail.com/dav/"),
    ]

    public static func status(_ account: SourceAccount) -> String {
        if account.locked { return "Connected on another device" }
        let count = account.items.count
        return count == 1 ? "1 item" : "\(count) items"
    }

    public static func problem(_ error: Error) -> String {
        switch error as? SourceError {
        case .unauthorized: return "The token was refused."
        case .unreadable: return "That address did not answer as expected."
        default: return "Couldn't reach that address."
        }
    }
}
