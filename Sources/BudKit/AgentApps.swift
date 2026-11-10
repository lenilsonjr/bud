import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// One model an app can run, as the picker lists it: its id for the app, the name shown and a
/// word on what it is for.
public struct AgentModel: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var note: String

    public init(id: String, name: String, note: String = "") {
        self.id = id
        self.name = name
        self.note = note
    }
}

/// An app that runs an agent on this Mac: what it is called, the command it installs, the files
/// it leaves once signed in, and the models it can run. The models are a fixed list for now;
/// `AgentApps` is where asking the install would go.
public struct AgentApp: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// The command on PATH that says the app is installed.
    public var executable: String
    /// Files under the home directory that the app writes once signed in and takes away on
    /// signing out; any one is enough. Empty when the app leaves no such file: the status then
    /// says installed and nothing about the sign-in.
    public var credentials: [String]
    public var models: [AgentModel]

    public init(id: String, name: String, executable: String, credentials: [String], models: [AgentModel]) {
        self.id = id
        self.name = name
        self.executable = executable
        self.credentials = credentials
        self.models = models
    }

    /// The model picked when the app is, the first in its list; none when it has no list.
    public var defaultModel: AgentModel? { models.first }

    /// Claude Code keeps its sign-in in the Keychain on a Mac, and `~/.claude.json` is written
    /// on any first run, signed in or not, so no file says whether it is signed in.
    public static let claudeCode = AgentApp(
        id: "claude-code", name: "Claude Code", executable: "claude",
        credentials: [],
        models: [
            AgentModel(id: "claude-fable-5-1", name: "Fable 5.1", note: "Newest"),
            AgentModel(id: "claude-opus-5-5", name: "Opus 5.5", note: "Most capable"),
            AgentModel(id: "claude-sonnet-5-5", name: "Sonnet 5.5", note: "Fast, everyday"),
            AgentModel(id: "claude-haiku-5-5", name: "Haiku 5.5", note: "Quickest"),
        ]
    )

    /// Codex writes `~/.codex/auth.json` on sign-in and removes it on sign-out.
    public static let codex = AgentApp(
        id: "codex", name: "Codex", executable: "codex",
        credentials: [".codex/auth.json"],
        models: [
            AgentModel(id: "gpt-5.3-codex", name: "GPT-5.3 Codex", note: "Most capable"),
            AgentModel(id: "gpt-5.3-codex-mini", name: "GPT-5.3 Codex mini", note: "Quickest"),
        ]
    )

    /// The apps Bud knows, in the order the picker lists them.
    public static let all = [claudeCode, codex]
}

/// What is on this Mac: which of the apps are installed and signed in, and the models each
/// can run. The look-up goes through the directories and the home it is given, so a test can
/// stand in a fake PATH and an empty home. This is the one place the apps and their models are
/// asked for: the picker lists what it says and the choice is checked against it.
public struct AgentApps: Equatable, Sendable {
    /// Where an app is installed and, when a file can say, whether it has signed in. The
    /// sign-in is nil when the app leaves no file that tracks it, or when the file's place
    /// cannot be read, as inside the app sandbox.
    public enum Status: Equatable, Sendable {
        case notInstalled
        case installed(signedIn: Bool?)

        /// The line under the app's name in the picker.
        public var line: String {
            switch self {
            case .notInstalled: return AgentText.notInstalled
            case .installed(signedIn: nil): return AgentText.installed
            case .installed(signedIn: true?): return AgentText.signedIn
            case .installed(signedIn: false?): return AgentText.notSignedIn
            }
        }

        public var isInstalled: Bool { self != .notInstalled }
    }

    /// An app as the picker lists it.
    public struct Entry: Identifiable, Equatable, Sendable {
        public var app: AgentApp
        public var status: Status

        public var id: String { app.id }
    }

    /// The directories a command is looked for in, in order.
    public var directories: [String]
    /// The home the credential markers are read under.
    public var home: URL
    /// The apps to look for.
    public var apps: [AgentApp]

    public init(directories: [String], home: URL, apps: [AgentApp] = AgentApp.all) {
        self.directories = directories
        self.home = home
        self.apps = apps
    }

    /// This Mac: the places the command line tools install to, then this process's PATH, under
    /// the person's real home. An app opened from the Finder gets launchd's short PATH, which
    /// is why the known places come first.
    public init(apps: [AgentApp] = AgentApp.all) {
        let home = Self.realHome()
        self.init(
            directories: Self.merged(Self.knownDirectories(under: home), path: ProcessInfo.processInfo.environment["PATH"] ?? ""),
            home: home,
            apps: apps
        )
    }

    /// The person's home as the system has it, not the app's container when it is sandboxed.
    public static func realHome() -> URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Where the command line tools go: a package's own bin, Homebrew's, the system's, npm's.
    public static func knownDirectories(under home: URL) -> [String] {
        [
            home.appendingPathComponent(".local/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            home.appendingPathComponent(".npm-global/bin").path,
        ]
    }

    /// PATH as a list of directories, the empty entries dropped.
    public static func split(path: String) -> [String] {
        path.split(separator: ":", omittingEmptySubsequences: true).map(String.init)
    }

    /// The known places and then PATH, each directory once.
    public static func merged(_ known: [String], path: String) -> [String] {
        var seen = Set<String>()
        return (known + split(path: path)).filter { seen.insert($0).inserted }
    }

    /// Where the app's command is, if it is in one of the directories and may be run.
    public func executable(of app: AgentApp) -> URL? {
        let files = FileManager.default
        for directory in directories {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(app.executable)
            var isDirectory: ObjCBool = false
            if files.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue, files.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// Whether the app left a sign-in behind: true with a marker, false with none where one
    /// could be seen, nil when the app has no marker or the home or the marker's folder cannot
    /// be read.
    public func signIn(of app: AgentApp) -> Bool? {
        guard !app.credentials.isEmpty else { return nil }
        let files = FileManager.default
        guard files.isReadableFile(atPath: home.path) else { return nil }
        var seen = false
        for marker in app.credentials {
            let url = home.appendingPathComponent(marker)
            if files.fileExists(atPath: url.path) { return true }
            let folder = url.deletingLastPathComponent().path
            if files.fileExists(atPath: folder), !files.isReadableFile(atPath: folder) { continue }
            seen = true
        }
        return seen ? false : nil
    }

    public func status(of app: AgentApp) -> Status {
        guard executable(of: app) != nil else { return .notInstalled }
        return .installed(signedIn: signIn(of: app))
    }

    /// Every app with what was found of it, in the picker's order.
    public var entries: [Entry] {
        apps.map { Entry(app: $0, status: status(of: $0)) }
    }

    /// The apps found on this Mac.
    public var installed: [AgentApp] {
        entries.filter(\.status.isInstalled).map(\.app)
    }

    public func app(named id: String) -> AgentApp? { apps.first { $0.id == id } }

    /// The models the app can run. A fixed list per app for now; this is where the install
    /// would be asked.
    public func models(for app: AgentApp) -> [AgentModel] { app.models }

    /// The model picked when the app is: the first it can run.
    public func defaultModel(for app: AgentApp) -> AgentModel? { models(for: app).first }

    /// The choice until something is picked: the first app and its first model.
    public var defaultChoice: AgentChoice {
        guard let app = apps.first else { return AgentChoice(app: "", model: "") }
        return AgentChoice(app: app.id, model: defaultModel(for: app)?.id ?? "")
    }
}

/// Which app runs the agent and with which model, as this device has it. Kept in the device's
/// defaults, not the vault: another Mac has its own installs. The pair is two ids; what they
/// name is asked of the `AgentApps` it is checked against.
public struct AgentChoice: Equatable, Codable, Sendable {
    public var app: String
    public var model: String

    public init(app: String, model: String) {
        self.app = app
        self.model = model
    }

    /// The key the choice is saved under.
    public static let key = "agentChoice"

    public func app(in apps: AgentApps) -> AgentApp? { apps.app(named: app) }

    public func model(in apps: AgentApps) -> AgentModel? {
        guard let app = app(in: apps) else { return nil }
        return apps.models(for: app).first { $0.id == model }
    }

    /// "Claude Code · Fable 5.1", as the composer names the pair.
    public func label(in apps: AgentApps) -> String {
        [app(in: apps)?.name, model(in: apps)?.name].compactMap { $0 }.joined(separator: " · ")
    }

    /// Picks an app; the model moves to that app's first unless it already is one of its.
    public mutating func choose(_ app: AgentApp, in apps: AgentApps) {
        self.app = app.id
        let models = apps.models(for: app)
        if !models.contains(where: { $0.id == model }) { model = apps.defaultModel(for: app)?.id ?? "" }
    }

    /// Picks a model of the chosen app; one of another app is ignored.
    public mutating func choose(_ model: AgentModel, in apps: AgentApps) {
        guard let app = app(in: apps), apps.models(for: app).contains(where: { $0.id == model.id }) else { return }
        self.model = model.id
    }

    /// The choice as it stands on a Mac: an app not known falls back to the default, a model
    /// not the app's to the app's first.
    public func repaired(in apps: AgentApps) -> AgentChoice {
        guard let app = app(in: apps) else { return apps.defaultChoice }
        var choice = self
        choice.choose(app, in: apps)
        return choice
    }

    /// Reads the choice saved on this device, or the default.
    public static func read(from defaults: UserDefaults, in apps: AgentApps) -> AgentChoice {
        guard let data = defaults.data(forKey: key), let choice = try? JSONDecoder().decode(AgentChoice.self, from: data) else {
            return apps.defaultChoice
        }
        return choice.repaired(in: apps)
    }

    /// Saves the choice on this device.
    public func write(to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }
}
