import XCTest
@testable import BudKit

final class AgentAppsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("agent-apps-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("home"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
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

    func testOnlyTheAppsOnThePathAreInstalledAndAMarkerMeansSignedIn() throws {
        try install("claude")
        try signIn(".claude.json")
        let apps = AgentApps(directories: ["/nowhere", bin], home: home)
        XCTAssertEqual(apps.status(of: .claudeCode), .installed(signedIn: true))
        XCTAssertEqual(apps.status(of: .codex), .notInstalled)
        XCTAssertEqual(apps.installed, [.claudeCode])
        XCTAssertEqual(apps.entries.map(\.app.name), ["Claude Code", "Codex"], "Both are listed, in order")
        XCTAssertEqual(apps.entries.map(\.status.line), ["Installed · signed in", "Not installed"])
        XCTAssertEqual(apps.executable(of: .claudeCode)?.lastPathComponent, "claude")
        XCTAssertEqual(apps.models(for: .claudeCode).map(\.id), ["claude-fable-5-1", "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"])
        XCTAssertEqual(apps.models(for: .codex).count, 2)
    }

    func testAnInstallWithoutAMarkerIsNotSignedIn() throws {
        try install("codex")
        try signIn(".claude/.credentials.json")
        let apps = AgentApps(directories: [bin], home: home)
        XCTAssertEqual(apps.status(of: .codex), .installed(signedIn: false))
        XCTAssertEqual(apps.status(of: .codex).line, "Installed · not signed in")
        XCTAssertEqual(apps.status(of: .claudeCode), .notInstalled, "A marker without the command is not an install")
        XCTAssertTrue(apps.isSignedIn(.claudeCode), "Either of Claude Code's markers counts")
        try signIn(".codex/auth.json")
        XCTAssertEqual(apps.status(of: .codex), .installed(signedIn: true))
    }

    func testAFileThatCannotRunOrADirectoryIsNotAnInstall() throws {
        try install("claude", executable: false)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("bin/codex"), withIntermediateDirectories: true)
        let apps = AgentApps(directories: [bin], home: home)
        XCTAssertEqual(apps.entries.map(\.status), [.notInstalled, .notInstalled])
        XCTAssertEqual(AgentApps(directories: [], home: home).installed, [], "An empty PATH finds nothing")
        XCTAssertEqual(AgentApps.split(path: "/usr/bin::/opt/bin:"), ["/usr/bin", "/opt/bin"])
    }

    func testTheChoiceFollowsTheAppAndKeepsToItsModels() {
        var choice = AgentChoice.default
        XCTAssertEqual(choice, AgentChoice(app: "claude-code", model: "claude-fable-5-1"))
        XCTAssertEqual(choice.label, "Claude Code · Fable 5.1")
        choice.choose(AgentApp.claudeCode.models[1])
        XCTAssertEqual(choice.model, "claude-opus-5-5")
        choice.choose(AgentApp.codex.models[1])
        XCTAssertEqual(choice.model, "claude-opus-5-5", "A model of another app is ignored")
        choice.choose(.codex)
        XCTAssertEqual(choice, AgentChoice(app: "codex", model: "gpt-5.3-codex"), "A new app brings its first model")
        XCTAssertEqual(choice.label, "Codex · GPT-5.3 Codex")
        choice.choose(AgentApp.codex.models[1])
        choice.choose(.codex)
        XCTAssertEqual(choice.model, "gpt-5.3-codex-mini", "Picking the same app again keeps its model")
        XCTAssertEqual(AgentChoice(app: "gone", model: "x").repaired, .default)
        XCTAssertEqual(AgentChoice(app: "codex", model: "x").repaired, AgentChoice(app: "codex", model: "gpt-5.3-codex"))
        XCTAssertEqual(AgentChoice(app: "gone", model: "x").label, "")
    }

    func testTheChoiceIsKeptInTheDevicesDefaults() {
        let defaults = UserDefaults(suiteName: "agent-\(UUID().uuidString)")!
        XCTAssertEqual(AgentChoice.read(from: defaults), .default)
        var choice = AgentChoice.default
        choice.choose(.codex)
        choice.write(to: defaults)
        XCTAssertEqual(AgentChoice.read(from: defaults), choice)
        AgentChoice(app: "gone", model: "x").write(to: defaults)
        XCTAssertEqual(AgentChoice.read(from: defaults), .default, "A saved app this build does not know falls back")
        defaults.set(Data("not json".utf8), forKey: AgentChoice.key)
        XCTAssertEqual(AgentChoice.read(from: defaults), .default)
    }

    #if canImport(SwiftUI)
    @MainActor
    func testTheStoreReadsTheChoiceBackOnTheSameDevice() {
        let before = UserDefaults.standard.data(forKey: AgentChoice.key)
        defer {
            if let before { UserDefaults.standard.set(before, forKey: AgentChoice.key) } else { UserDefaults.standard.removeObject(forKey: AgentChoice.key) }
        }
        UserDefaults.standard.removeObject(forKey: AgentChoice.key)
        let store = BudStore(vault: MemoryVault(tree: Tree()))
        XCTAssertEqual(store.agentChoice, .default)
        store.agentChoice.choose(.codex)
        store.agentChoice.choose(AgentApp.codex.models[1])
        let again = BudStore(vault: MemoryVault(tree: Tree()))
        XCTAssertEqual(again.agentChoice, AgentChoice(app: "codex", model: "gpt-5.3-codex-mini"))
    }
    #endif
}
