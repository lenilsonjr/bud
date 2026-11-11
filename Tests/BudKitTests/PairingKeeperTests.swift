import XCTest
@testable import BudKit

final class PairingKeeperTests: XCTestCase {
    func testItKeepsAPairingAndGivesItBack() throws {
        let keeper = PairingKeeper(store: MemoryTokens(), defaults: try freshDefaults())
        XCTAssertNil(keeper.kept)
        keeper.keep(Data([1, 2, 3]))
        XCTAssertEqual(keeper.kept, Data([1, 2, 3]))
        keeper.keep(Data([4, 5]))
        XCTAssertEqual(keeper.kept, Data([4, 5]))
    }

    func testAnUnpairedVaultLetsTheKeptCopyGo() throws {
        let keeper = PairingKeeper(store: MemoryTokens(), defaults: try freshDefaults())
        keeper.keep(Data([1, 2, 3]))
        // Its node key and no peers: the person removed the last one.
        keeper.keep(nil)
        XCTAssertNil(keeper.kept)
    }

    func testKeepingFindsAnUnpairedVaultOnItsOwn() async throws {
        let keeper = PairingKeeper(store: MemoryTokens(), defaults: try freshDefaults())
        keeper.keep(Data([1]))
        let sync = PairingSync(keeper: keeper) { nil }
        await sync.keep()
        XCTAssertNil(keeper.kept)
    }

    func testOnlyForgetLetsItGo() throws {
        let tokens = MemoryTokens()
        let keeper = PairingKeeper(store: tokens, defaults: try freshDefaults())
        keeper.keep(Data([1, 2, 3]))
        keeper.forget()
        XCTAssertNil(keeper.kept)
        XCTAssertNil(tokens.token(for: PairingKeeper.account))
    }

    func testADamagedCopyReadsAsNone() throws {
        let tokens = MemoryTokens([PairingKeeper.account: "not base64 at all!"])
        XCTAssertNil(PairingKeeper(store: tokens, defaults: try freshDefaults()).kept)
    }

    func testTheSamePairingIsNotWrittenAgain() throws {
        let tokens = CountingTokens()
        let keeper = PairingKeeper(store: tokens, defaults: try freshDefaults())
        keeper.keep(Data([1, 2, 3]))
        keeper.keep(Data([1, 2, 3]))
        keeper.keep(nil)
        keeper.keep(nil)
        keeper.forget()
        XCTAssertEqual(tokens.writes, 2)
    }

    func testAFailedWriteSaysSoAndLeavesTheCopyBefore() throws {
        let tokens = RefusingTokens()
        let keeper = PairingKeeper(store: tokens, defaults: try freshDefaults())
        XCTAssertTrue(keeper.keep(Data([1])))
        tokens.refusing = true
        XCTAssertFalse(keeper.keep(Data([2])))
        XCTAssertFalse(keeper.forget())
        XCTAssertEqual(keeper.kept, Data([1]))
    }

    func testTheSameInstallFindsItsCopyOnTheNextLaunch() throws {
        let tokens = MemoryTokens()
        let defaults = try freshDefaults()
        PairingKeeper(store: tokens, defaults: defaults).keep(Data([1, 2, 3]))
        XCTAssertEqual(PairingKeeper(store: tokens, defaults: defaults).kept, Data([1, 2, 3]))
    }

    func testAnAppInstalledAgainNeverRejoinsWithTheOldCopy() throws {
        // The Keychain outlives the app; its defaults do not.
        let tokens = MemoryTokens()
        PairingKeeper(store: tokens, defaults: try freshDefaults()).keep(Data([1, 2, 3]))
        let reinstalled = PairingKeeper(store: tokens, defaults: try freshDefaults())
        XCTAssertNil(reinstalled.kept)
        reinstalled.dropForeign()
        XCTAssertNil(tokens.token(for: PairingKeeper.account))
    }

    func testACopyWithNoInstallIdIsDropped() throws {
        let tokens = MemoryTokens([PairingKeeper.account: Data([1, 2, 3]).base64EncodedString()])
        let keeper = PairingKeeper(store: tokens, defaults: try freshDefaults())
        XCTAssertNil(keeper.kept)
        keeper.dropForeign()
        XCTAssertNil(tokens.token(for: PairingKeeper.account))
    }

    func testDroppingLeavesThisInstallsOwnCopy() throws {
        let keeper = PairingKeeper(store: MemoryTokens(), defaults: try freshDefaults())
        keeper.keep(Data([1]))
        keeper.dropForeign()
        XCTAssertEqual(keeper.kept, Data([1]))
    }

    func testForgetDeletesADamagedCopyToo() throws {
        let tokens = MemoryTokens([PairingKeeper.account: "garbled"])
        let keeper = PairingKeeper(store: tokens, defaults: try freshDefaults())
        XCTAssertTrue(keeper.forget())
        XCTAssertNil(tokens.token(for: PairingKeeper.account))
    }

    func testAStaleForgetLeavesAPairingMadeSince() async throws {
        let keeper = PairingKeeper(store: MemoryTokens(), defaults: try freshDefaults())
        // The device paired again before the forget asked when it had none ran.
        let sync = PairingSync(keeper: keeper) { Data([2]) }
        await sync.keep()
        await sync.forget()
        XCTAssertEqual(keeper.kept, Data([2]))
    }

    func testForgetLetsGoWhenTheVaultIsStillUnpaired() async throws {
        let keeper = PairingKeeper(store: MemoryTokens(), defaults: try freshDefaults())
        keeper.keep(Data([1]))
        let sync = PairingSync(keeper: keeper) { nil }
        await sync.forget()
        XCTAssertNil(keeper.kept)
    }

    func testForgetLeavesTheCopyWhenTheVaultCannotBeRead() async throws {
        let keeper = PairingKeeper(store: MemoryTokens(), defaults: try freshDefaults())
        keeper.keep(Data([1]))
        struct Locked: Error {}
        let sync = PairingSync(keeper: keeper) { throw Locked() }
        await sync.forget()
        XCTAssertEqual(keeper.kept, Data([1]))
    }

    func testStepsRunOneAtATimeSoTheLastReadIsWhatStays() async throws {
        let keeper = PairingKeeper(store: MemoryTokens(), defaults: try freshDefaults())
        let vault = CountingVault()
        let sync = PairingSync(keeper: keeper) { vault.next() }
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 { group.addTask { await sync.keep() } }
        }
        XCTAssertEqual(keeper.kept, Data([50]))
    }

    func testAPairingThatCannotBeReadLeavesTheKeptOne() async throws {
        let keeper = PairingKeeper(store: MemoryTokens(), defaults: try freshDefaults())
        keeper.keep(Data([7]))
        struct Locked: Error {}
        let sync = PairingSync(keeper: keeper) { throw Locked() }
        await sync.keep()
        XCTAssertEqual(keeper.kept, Data([7]))
    }

    func testALaunchReadsTheKeychainOnce() async throws {
        let defaults = try freshDefaults()
        let tokens = CountingTokens()
        PairingKeeper(store: tokens, defaults: defaults).keep(Data([1, 2, 3]))
        let counted = CountingTokens([PairingKeeper.account: try XCTUnwrap(tokens.token(for: PairingKeeper.account))])
        let keeper = try XCTUnwrap(PairingKeeper.forLaunch(platform: .tvOS, arguments: ["Bud"]) {
            PairingKeeper(store: counted, defaults: defaults)
        })
        XCTAssertEqual(keeper.kept, Data([1, 2, 3]))
        // The first keep after the launch finds the same pairing, and the next one a new one.
        let sync = PairingSync(keeper: keeper) { Data([1, 2, 3]) }
        await sync.keep()
        keeper.keep(Data([4]))
        XCTAssertEqual(keeper.kept, Data([4]))
        XCTAssertEqual(counted.reads, 1)
        XCTAssertEqual(counted.writes, 1)
    }

    func testAFailedWriteReadsTheKeychainAgain() throws {
        let tokens = RefusingTokens()
        let keeper = PairingKeeper(store: tokens, defaults: try freshDefaults())
        keeper.keep(Data([1]))
        tokens.refusing = true
        keeper.keep(Data([2]))
        tokens.refusing = false
        XCTAssertEqual(keeper.kept, Data([1]), "what the Keychain holds, not what was asked")
    }

    func testToursAndPicturesBuildNoKeeper() throws {
        let tokens = CountingTokens([PairingKeeper.account: "another-install:AQID"])
        let defaults = try freshDefaults()
        for arguments in [["Bud", "-bud-pictures"], ["Bud", MemoryPeers.pairedArgument], ["Bud", "-bud-nearby"]] {
            var made = 0
            let keeper = PairingKeeper.forLaunch(platform: .tvOS, arguments: arguments) {
                made += 1
                return PairingKeeper(store: tokens, defaults: defaults)
            }
            XCTAssertNil(keeper, "\(arguments)")
            XCTAssertEqual(made, 0, "\(arguments)")
        }
        XCTAssertEqual(tokens.reads, 0)
        XCTAssertEqual(tokens.writes, 0, "another install's copy is left alone too")
    }

    func testOnlyTheTVKeepsItsPairing() {
        for platform in [VaultPlatform.macOS, .iOS] {
            var made = 0
            let keeper = PairingKeeper.forLaunch(platform: platform, arguments: ["Bud"]) {
                made += 1
                return PairingKeeper(store: MemoryTokens(), defaults: .standard)
            }
            XCTAssertNil(keeper)
            XCTAssertEqual(made, 0)
        }
    }

    func testATVLaunchDropsAnotherInstallsCopy() throws {
        let tokens = MemoryTokens([PairingKeeper.account: "another-install:AQID"])
        let defaults = try freshDefaults()
        let keeper = PairingKeeper.forLaunch(platform: .tvOS, arguments: ["Bud"]) {
            PairingKeeper(store: tokens, defaults: defaults)
        }
        XCTAssertNotNil(keeper)
        XCTAssertNil(tokens.token(for: PairingKeeper.account))
    }

    func testTheTimerKeepsUntilStopped() async throws {
        let keeper = PairingKeeper(store: MemoryTokens(), defaults: try freshDefaults())
        let vault = CountingVault()
        let sync = PairingSync(keeper: keeper) { vault.next() }
        await sync.start(every: 0.01)
        for _ in 0..<200 where (keeper.kept?.first ?? 0) < 2 {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertGreaterThanOrEqual(keeper.kept?.first ?? 0, 2)
        await sync.stop()
        let stopped = vault.count
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(vault.count, stopped)
    }
}

/// A vault whose pairing changes on every read: the first read is [1], the next [2], and so on.
private final class CountingVault: @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return reads
    }

    func next() -> Data {
        lock.lock(); defer { lock.unlock() }
        reads += 1
        return Data([UInt8(reads)])
    }
}

/// Tokens in memory that refuse every write while `refusing`, as a locked Keychain would.
private final class RefusingTokens: TokenStore, @unchecked Sendable {
    private let inner = MemoryTokens()
    var refusing = false

    func token(for account: String) -> String? { inner.token(for: account) }

    @discardableResult
    func set(_ token: String?, for account: String) -> Bool {
        refusing ? false : inner.set(token, for: account)
    }
}

/// Tokens in memory that count their reads and writes.
private final class CountingTokens: TokenStore, @unchecked Sendable {
    private let inner: MemoryTokens
    private(set) var reads = 0
    private(set) var writes = 0

    init(_ tokens: [String: String] = [:]) { inner = MemoryTokens(tokens) }

    func token(for account: String) -> String? {
        reads += 1
        return inner.token(for: account)
    }

    @discardableResult
    func set(_ token: String?, for account: String) -> Bool {
        writes += 1
        return inner.set(token, for: account)
    }
}
