import XCTest
@testable import BudKit

final class VaultPathsTests: XCTestCase {
    private let base = URL(fileURLWithPath: "/containers/bud", isDirectory: true)

    private func paths(_ platform: VaultPlatform) -> VaultPaths {
        VaultPaths(platform: platform, base: base)
    }

    func testTheMacKeepsTheVaultInDocumentsAndTheIndexInSupportFiles() {
        let mac = paths(.macOS)
        XCTAssertEqual(mac.vaultFolder.path, "/containers/bud/Documents/Bud")
        XCTAssertEqual(mac.indexFolder.path, "/containers/bud/Library/Application Support/Bud")
        XCTAssertEqual(mac.indexFile.path, "/containers/bud/Library/Application Support/Bud/index.db")
    }

    func testThePhoneUsesTheSamePlacesAsTheMac() {
        XCTAssertEqual(paths(.iOS).vaultFolder, paths(.macOS).vaultFolder)
        XCTAssertEqual(paths(.iOS).indexFolder, paths(.macOS).indexFolder)
    }

    func testTheTVKeepsBothUnderCaches() {
        let tv = paths(.tvOS)
        XCTAssertEqual(tv.vaultFolder.path, "/containers/bud/Library/Caches/Bud/Vault")
        XCTAssertEqual(tv.indexFolder.path, "/containers/bud/Library/Caches/Bud/Index")
        XCTAssertTrue(tv.vaultFolder.path.hasPrefix("/containers/bud/Library/Caches/"))
        XCTAssertTrue(tv.indexFolder.path.hasPrefix("/containers/bud/Library/Caches/"))
    }

    func testTheVaultAndTheIndexNeverShareAFolder() {
        for platform in [VaultPlatform.macOS, .iOS, .tvOS] {
            let p = paths(platform)
            XCTAssertNotEqual(p.vaultFolder, p.indexFolder)
            XCTAssertFalse(p.indexFolder.path.hasPrefix(p.vaultFolder.path + "/"))
            XCTAssertFalse(p.vaultFolder.path.hasPrefix(p.indexFolder.path + "/"))
        }
    }

    func testOnlyAClearedCacheOnTheTVFetchesFromAPeer() {
        XCTAssertTrue(paths(.tvOS).fetchesFromPeer(indexIsMissing: true))
        XCTAssertFalse(paths(.tvOS).fetchesFromPeer(indexIsMissing: false))
        XCTAssertFalse(paths(.macOS).fetchesFromPeer(indexIsMissing: true))
        XCTAssertFalse(paths(.iOS).fetchesFromPeer(indexIsMissing: true))
    }

    /// A container in a fresh temporary folder.
    private func temporary(_ platform: VaultPlatform) -> VaultPaths {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        return VaultPaths(platform: platform, base: base)
    }

    func testAnEmptyFolderBesideItsIndexOpensAsItIs() throws {
        let tv = temporary(.tvOS)
        try FileManager.default.createDirectory(at: tv.vaultFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tv.indexFolder, withIntermediateDirectories: true)
        try Data("index".utf8).write(to: tv.indexFile)
        XCTAssertFalse(tv.fetchesFromPeer())
        XCTAssertTrue(FileManager.default.fileExists(atPath: tv.indexFile.path), "the index stays")
    }

    func testANodeKeyLeftBehindIsNoClearedCache() throws {
        let tv = temporary(.tvOS)
        try FileManager.default.createDirectory(at: tv.indexFolder, withIntermediateDirectories: true)
        try Data(count: 32).write(to: tv.nodeKeyFile)
        XCTAssertFalse(tv.fetchesFromPeer())
    }

    func testAClearedCacheFetches() {
        let tv = temporary(.tvOS)
        XCTAssertTrue(tv.fetchesFromPeer())
    }

    func testAnIndexGoneWhileBudsRemainStillFetches() throws {
        let tv = temporary(.tvOS)
        try FileManager.default.createDirectory(at: tv.vaultFolder, withIntermediateDirectories: true)
        try Data("A note.\n".utf8).write(to: tv.vaultFolder.appendingPathComponent("Gift ideas.md"))
        XCTAssertTrue(tv.fetchesFromPeer())
    }

    func testLeftoversInTheTVFolderGoAndTheFolderStays() throws {
        let tv = temporary(.tvOS)
        let files = FileManager.default
        try files.createDirectory(at: tv.vaultFolder.appendingPathComponent("Routines"), withIntermediateDirectories: true)
        try Data().write(to: tv.vaultFolder.appendingPathComponent("Gift ideas.md"))
        try Data().write(to: tv.vaultFolder.appendingPathComponent("Routines/Weekly review.md"))
        tv.emptyVaultFolder()
        XCTAssertEqual(try files.contentsOfDirectory(atPath: tv.vaultFolder.path), [])
    }

    func testTheMacFolderIsNeverEmptied() throws {
        let mac = temporary(.macOS)
        try FileManager.default.createDirectory(at: mac.vaultFolder, withIntermediateDirectories: true)
        try Data().write(to: mac.vaultFolder.appendingPathComponent("Gift ideas.md"))
        mac.emptyVaultFolder()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: mac.vaultFolder.path), ["Gift ideas.md"])
    }

    func testTheMacNeverFetchesForAMissingIndex() {
        XCTAssertFalse(temporary(.macOS).fetchesFromPeer())
    }
}
