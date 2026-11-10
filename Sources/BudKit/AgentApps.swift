import Foundation

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
    /// Files under the home directory that the app writes once signed in; any one is enough.
    public var credentials: [String]
    public var models: [AgentModel]

    public init(id: String, name: String, executable: String, credentials: [String], models: [AgentModel]) {
        self.id = id
        self.name = name
        self.executable = executable
        self.credentials = credentials
        self.models = models
    }

    /// The model picked when the app is, the first in its list.
    public var defaultModel: AgentModel { models[0] }

    public static let claudeCode = AgentApp(
        id: "claude-code", name: "Claude Code", executable: "claude",
        credentials: [".claude/.credentials.json", ".claude.json"],
        models: [
            AgentModel(id: "claude-fable-5-1", name: "Fable 5.1", note: "Newest"),
            AgentModel(id: "claude-opus-5-5", name: "Opus 5.5", note: "Most capable"),
            AgentModel(id: "claude-sonnet-5-5", name: "Sonnet 5.5", note: "Fast, everyday"),
            AgentModel(id: "claude-haiku-5-5", name: "Haiku 5.5", note: "Quickest"),
        ]
    )

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

    public static func named(_ id: String) -> AgentApp? { all.first { $0.id == id } }
}

/// What is on this Mac: which of the apps are installed and signed in, and the models each
/// can run. The look-up goes through the directories and the home it is given, so a test can
/// stand in a fake PATH and an empty home.
public struct AgentApps: Equatable, Sendable {
    /// Where an app is installed and whether it has signed in.
    public enum Status: Equatable, Sendable {
        case notInstalled
        case installed(signedIn: Bool)

        /// The line under the app's name in the picker.
        public var line: String {
            switch self {
            case .notInstalled: return AgentText.notInstalled
            case .installed(signedIn: true): return AgentText.signedIn
            case .installed(signedIn: false): return AgentText.notSignedIn
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

    /// The directories a command is looked for in, PATH in order.
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

    /// This process's PATH and home.
    public init(apps: [AgentApp] = AgentApp.all) {
        self.init(
            directories: Self.split(path: ProcessInfo.processInfo.environment["PATH"] ?? ""),
            home: FileManager.default.homeDirectoryForCurrentUser,
            apps: apps
        )
    }

    /// PATH as a list of directories, the empty entries dropped.
    public static func split(path: String) -> [String] {
        path.split(separator: ":", omittingEmptySubsequences: true).map(String.init)
    }

    /// Where the app's command is, if it is on PATH and may be run.
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

    /// Whether the app left a sign-in behind.
    public func isSignedIn(_ app: AgentApp) -> Bool {
        app.credentials.contains { FileManager.default.fileExists(atPath: home.appendingPathComponent($0).path) }
    }

    public func status(of app: AgentApp) -> Status {
        guard executable(of: app) != nil else { return .notInstalled }
        return .installed(signedIn: isSignedIn(app))
    }

    /// Every app with what was found of it, in the picker's order.
    public var entries: [Entry] {
        apps.map { Entry(app: $0, status: status(of: $0)) }
    }

    /// The apps found on this Mac.
    public var installed: [AgentApp] {
        entries.filter(\.status.isInstalled).map(\.app)
    }

    /// The models the app can run. A fixed list per app for now; this is where the install
    /// would be asked.
    public func models(for app: AgentApp) -> [AgentModel] { app.models }
}

/// Which app runs the agent and with which model, as this device has it. Kept in the device's
/// defaults, not the vault: another Mac has its own installs.
public struct AgentChoice: Equatable, Codable, Sendable {
    public var app: String
    public var model: String

    public init(app: String, model: String) {
        self.app = app
        self.model = model
    }

    /// Claude Code and its first model, until something is picked.
    public static let `default` = AgentChoice(app: AgentApp.claudeCode.id, model: AgentApp.claudeCode.defaultModel.id)

    /// The key the choice is saved under.
    public static let key = "agentChoice"

    /// Picks an app; the model moves to that app's first unless it already is one of its.
    public mutating func choose(_ app: AgentApp) {
        self.app = app.id
        if !app.models.contains(where: { $0.id == model }) { model = app.defaultModel.id }
    }

    /// Picks a model of the chosen app; one of another app is ignored.
    public mutating func choose(_ model: AgentModel) {
        guard chosenApp?.models.contains(model) == true else { return }
        self.model = model.id
    }

    public var chosenApp: AgentApp? { AgentApp.named(app) }

    public var chosenModel: AgentModel? { chosenApp?.models.first { $0.id == model } }

    /// "Claude Code · Fable 5.1", as the composer names the pair.
    public var label: String {
        [chosenApp?.name, chosenModel?.name].compactMap { $0 }.joined(separator: " · ")
    }

    /// The choice as it stands on a Mac: an app no longer known falls back to the default.
    public var repaired: AgentChoice {
        guard let app = chosenApp else { return .default }
        var choice = self
        choice.choose(app)
        return choice
    }

    /// Reads the choice saved on this device, or the default.
    public static func read(from defaults: UserDefaults) -> AgentChoice {
        guard let data = defaults.data(forKey: key), let choice = try? JSONDecoder().decode(AgentChoice.self, from: data) else {
            return .default
        }
        return choice.repaired
    }

    /// Saves the choice on this device.
    public func write(to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }
}
