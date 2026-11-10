import XCTest
@testable import BudKit
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

final class AgentAppsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("agent-apps-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("home"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // A folder a test shut is opened again so it can go.
        for folder in [home.appendingPathComponent(".codex"), home] {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        }
        try? FileManager.default.removeItem(at: root)
    }

    private var bin: String { root.appendingPathComponent("bin").path }
    private var home: URL { root.appendingPathComponent("home") }

    /// Puts a command in the fake PATH, runnable unless told otherwise.
    private func install(_ name: String, executable: Bool = true) throws {
        let url = root.appendingPathComponent("bin").appendingPathComponent(name)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
    }

    /// Leaves an empty marker where the app keeps its sign-in.
    private func signIn(_ marker: String) throws {
        let url = home.appendingPathComponent(marker)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
    }

    /// Root reads any folder, so a test about an unreadable one has nothing to say there.
    private var canShutAFolder: Bool { geteuid() != 0 }

    // MARK: Installs

    func testOnlyTheAppsOnThePathAreInstalledAndAMarkerMeansSignedIn() throws {
        try install("codex")
        try signIn(".codex/auth.json")
        let apps = AgentApps(directories: ["/nowhere", bin], home: home)
        XCTAssertEqual(apps.status(of: .codex), .installed(signedIn: true))
        XCTAssertEqual(apps.status(of: .claudeCode), .notInstalled)
        XCTAssertEqual(apps.installed, [.codex])
        XCTAssertEqual(apps.entries.map(\.app.name), ["Claude Code", "Codex"], "Both are listed, in order")
        XCTAssertEqual(apps.entries.map(\.status.line), ["Not installed", "Installed · signed in"])
        XCTAssertEqual(apps.executable(of: .codex)?.lastPathComponent, "codex")
        XCTAssertEqual(apps.models(for: .claudeCode).map(\.id), ["claude-fable-5-1", "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"])
        XCTAssertEqual(apps.models(for: .codex).count, 2)
        XCTAssertEqual(apps.app(named: "codex"), .codex)
        XCTAssertNil(apps.app(named: "gone"))
    }

    func testAnInstallWithoutAMarkerIsNotSignedInAndOneWithoutAnyMarkerFileSaysInstalledAlone() throws {
        try install("codex")
        try install("claude")
        let apps = AgentApps(directories: [bin], home: home)
        XCTAssertEqual(apps.status(of: .codex), .installed(signedIn: false))
        XCTAssertEqual(apps.status(of: .codex).line, "Installed · not signed in")
        XCTAssertEqual(apps.status(of: .claudeCode), .installed(signedIn: nil), "Claude Code keeps its sign-in where no file says")
        XCTAssertEqual(apps.status(of: .claudeCode).line, "Installed")
        XCTAssertTrue(AgentApp.claudeCode.credentials.isEmpty)
        try signIn(".codex/auth.json")
        XCTAssertEqual(apps.status(of: .codex), .installed(signedIn: true))
        XCTAssertEqual(AgentApps(directories: [], home: home).status(of: .codex), .notInstalled, "A marker without the command is not an install")
    }

    func testAFolderThatCannotBeReadMakesNoClaimAboutTheSignIn() throws {
        try XCTSkipUnless(canShutAFolder)
        try install("codex")
        let codex = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: codex.path)
        let apps = AgentApps(directories: [bin], home: home)
        XCTAssertEqual(apps.status(of: .codex), .installed(signedIn: nil), "The marker's folder is shut, as under the sandbox")
        XCTAssertEqual(apps.status(of: .codex).line, "Installed")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: home.path)
        XCTAssertEqual(apps.status(of: .codex), .installed(signedIn: nil), "A home that cannot be read says nothing either")
        XCTAssertEqual(apps.status(of: .claudeCode), .notInstalled, "The install is still found on PATH")
    }

    func testAFileThatCannotRunOrADirectoryIsNotAnInstall() throws {
        try install("claude", executable: false)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("bin/codex"), withIntermediateDirectories: true)
        let apps = AgentApps(directories: [bin], home: home)
        XCTAssertEqual(apps.entries.map(\.status), [.notInstalled, .notInstalled])
        XCTAssertEqual(AgentApps(directories: [], home: home).installed, [], "An empty PATH finds nothing")
    }

    func testTheKnownInstallPlacesComeBeforeThePathAndEachOnce() {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        XCTAssertEqual(
            AgentApps.knownDirectories(under: home),
            ["/Users/someone/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/Users/someone/.npm-global/bin"]
        )
        XCTAssertEqual(AgentApps.split(path: "/usr/bin::/opt/bin:"), ["/usr/bin", "/opt/bin"])
        XCTAssertEqual(
            AgentApps.merged(["/opt/homebrew/bin", "/usr/local/bin"], path: "/usr/local/bin:/usr/bin:/opt/homebrew/bin:/usr/bin"),
            ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        )
        let mine = AgentApps()
        XCTAssertTrue(mine.directories.contains("/usr/local/bin"), "The known places are there even off a short PATH")
        XCTAssertEqual(mine.directories.count, Set(mine.directories).count)
        XCTAssertFalse(AgentApps.realHome().path.isEmpty)
        XCTAssertTrue(mine.home.hasDirectoryPath)
    }

    // MARK: Choice

    private var both: AgentApps { AgentApps(directories: [], home: home) }

    func testTheChoiceFollowsTheAppAndKeepsToItsModels() {
        let apps = both
        var choice = apps.defaultChoice
        XCTAssertEqual(choice, AgentChoice(app: "claude-code", model: "claude-fable-5-1"))
        XCTAssertEqual(choice.label(in: apps), "Claude Code · Fable 5.1")
        choice.choose(AgentApp.claudeCode.models[1], in: apps)
        XCTAssertEqual(choice.model, "claude-opus-5-5")
        choice.choose(AgentApp.codex.models[1], in: apps)
        XCTAssertEqual(choice.model, "claude-opus-5-5", "A model of another app is ignored")
        choice.choose(AgentModel(id: "claude-haiku-5-5", name: "Another name", note: "and note"), in: apps)
        XCTAssertEqual(choice.model, "claude-haiku-5-5", "A model is matched by its id")
        choice.choose(.codex, in: apps)
        XCTAssertEqual(choice, AgentChoice(app: "codex", model: "gpt-5.3-codex"), "A new app brings its first model")
        XCTAssertEqual(choice.label(in: apps), "Codex · GPT-5.3 Codex")
        choice.choose(AgentApp.codex.models[1], in: apps)
        choice.choose(.codex, in: apps)
        XCTAssertEqual(choice.model, "gpt-5.3-codex-mini", "Picking the same app again keeps its model")
        XCTAssertEqual(AgentChoice(app: "gone", model: "x").repaired(in: apps), apps.defaultChoice)
        XCTAssertEqual(AgentChoice(app: "codex", model: "x").repaired(in: apps), AgentChoice(app: "codex", model: "gpt-5.3-codex"))
        XCTAssertEqual(AgentChoice(app: "gone", model: "x").label(in: apps), "")
        XCTAssertNil(AgentChoice(app: "codex", model: "x").model(in: apps))
    }

    func testAnAppWithoutModelsAndNoAppsAtAllDoNotTrap() {
        let bare = AgentApp(id: "bare", name: "Bare", executable: "bare", credentials: [], models: [])
        XCTAssertNil(bare.defaultModel)
        let apps = AgentApps(directories: [], home: home, apps: [bare])
        XCTAssertEqual(apps.defaultChoice, AgentChoice(app: "bare", model: ""))
        XCTAssertNil(apps.defaultModel(for: bare))
        var choice = AgentChoice(app: "bare", model: "x")
        choice.choose(bare, in: apps)
        XCTAssertEqual(choice.model, "")
        XCTAssertEqual(choice.repaired(in: apps), AgentChoice(app: "bare", model: ""))
        XCTAssertEqual(choice.label(in: apps), "Bare")
        let none = AgentApps(directories: [], home: home, apps: [])
        XCTAssertEqual(none.defaultChoice, AgentChoice(app: "", model: ""))
        XCTAssertEqual(AgentChoice(app: "codex", model: "x").repaired(in: none), AgentChoice(app: "", model: ""))
        XCTAssertEqual(none.entries, [])
    }

    func testTheChoiceIsCheckedAgainstTheAppsItIsGiven() {
        let codexOnly = AgentApps(directories: [], home: home, apps: [.codex])
        XCTAssertEqual(codexOnly.defaultChoice, AgentChoice(app: "codex", model: "gpt-5.3-codex"))
        var choice = AgentChoice(app: "claude-code", model: "claude-opus-5-5")
        XCTAssertNil(choice.app(in: codexOnly), "An app the install does not list is not chosen")
        XCTAssertEqual(choice.repaired(in: codexOnly), codexOnly.defaultChoice)
        choice.choose(AgentApp.claudeCode.models[0], in: codexOnly)
        XCTAssertEqual(choice.model, "claude-opus-5-5", "Nothing to check the model against, so nothing moves")
    }

    // MARK: Per device

    func testTheChoiceIsKeptInTheDevicesDefaults() {
        let apps = both
        let defaults = UserDefaults(suiteName: "agent-\(UUID().uuidString)")!
        XCTAssertEqual(AgentChoice.read(from: defaults, in: apps), apps.defaultChoice)
        var choice = apps.defaultChoice
        choice.choose(.codex, in: apps)
        choice.write(to: defaults)
        XCTAssertEqual(AgentChoice.read(from: defaults, in: apps), choice)
        AgentChoice(app: "gone", model: "x").write(to: defaults)
        XCTAssertEqual(AgentChoice.read(from: defaults, in: apps), apps.defaultChoice, "A saved app this build does not know falls back")
        defaults.set(Data("not json".utf8), forKey: AgentChoice.key)
        XCTAssertEqual(AgentChoice.read(from: defaults, in: apps), apps.defaultChoice)
    }

    #if canImport(SwiftUI)
    @MainActor
    func testTheStoreReadsTheChoiceBackFromItsOwnDefaults() {
        let apps = both
        let defaults = UserDefaults(suiteName: "agent-store-\(UUID().uuidString)")!
        let store = BudStore(vault: MemoryVault(tree: Tree()), defaults: defaults, agentApps: apps)
        XCTAssertEqual(store.agentChoice, apps.defaultChoice)
        XCTAssertNil(defaults.data(forKey: AgentChoice.key), "Nothing is written until something is picked")
        store.agentChoice.choose(.codex, in: apps)
        store.agentChoice.choose(AgentApp.codex.models[1], in: apps)
        let again = BudStore(vault: MemoryVault(tree: Tree()), defaults: defaults, agentApps: apps)
        XCTAssertEqual(again.agentChoice, AgentChoice(app: "codex", model: "gpt-5.3-codex-mini"))
        let other = BudStore(vault: MemoryVault(tree: Tree()), defaults: UserDefaults(suiteName: "agent-other-\(UUID().uuidString)")!, agentApps: apps)
        XCTAssertEqual(other.agentChoice, apps.defaultChoice, "Another device starts from the default")
    }
    #endif
}
