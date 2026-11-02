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

    func testOnlyAnEmptyVaultOnTheTVFetchesFromAPeer() {
        XCTAssertTrue(paths(.tvOS).fetchesFromPeer(vaultFolderIsEmpty: true))
        XCTAssertFalse(paths(.tvOS).fetchesFromPeer(vaultFolderIsEmpty: false))
        XCTAssertFalse(paths(.macOS).fetchesFromPeer(vaultFolderIsEmpty: true))
        XCTAssertFalse(paths(.iOS).fetchesFromPeer(vaultFolderIsEmpty: true))
    }
}
