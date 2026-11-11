import XCTest
@testable import BudKit

final class PairingKeeperTests: XCTestCase {
    func testItKeepsAPairingAndGivesItBack() {
        let keeper = PairingKeeper(store: MemoryTokens())
        XCTAssertNil(keeper.kept)
        keeper.keep(Data([1, 2, 3]))
        XCTAssertEqual(keeper.kept, Data([1, 2, 3]))
        keeper.keep(Data([4, 5]))
        XCTAssertEqual(keeper.kept, Data([4, 5]))
    }

    func testAVaultWithNoPeerNeverTakesTheKeptCopyAway() {
        let keeper = PairingKeeper(store: MemoryTokens())
        keeper.keep(Data([1, 2, 3]))
        // A fresh key with no peers, after a restore that failed, reads as no pairing.
        keeper.keep(nil)
        XCTAssertEqual(keeper.kept, Data([1, 2, 3]))
    }

    func testOnlyForgetLetsItGo() {
        let tokens = MemoryTokens()
        let keeper = PairingKeeper(store: tokens)
        keeper.keep(Data([1, 2, 3]))
        keeper.forget()
        XCTAssertNil(keeper.kept)
        XCTAssertNil(tokens.token(for: PairingKeeper.account))
    }

    func testADamagedCopyReadsAsNone() {
        let tokens = MemoryTokens([PairingKeeper.account: "not base64 at all!"])
        XCTAssertNil(PairingKeeper(store: tokens).kept)
    }

    func testTheSamePairingIsNotWrittenAgain() {
        let tokens = CountingTokens()
        let keeper = PairingKeeper(store: tokens)
        keeper.keep(Data([1, 2, 3]))
        keeper.keep(Data([1, 2, 3]))
        keeper.keep(nil)
        keeper.forget()
        keeper.forget()
        XCTAssertEqual(tokens.writes, 2)
    }

    func testAFailedWriteSaysSoAndLeavesTheCopyBefore() {
        let tokens = RefusingTokens()
        let keeper = PairingKeeper(store: tokens)
        XCTAssertTrue(keeper.keep(Data([1])))
        tokens.refusing = true
        XCTAssertFalse(keeper.keep(Data([2])))
        XCTAssertFalse(keeper.forget())
        XCTAssertEqual(keeper.kept, Data([1]))
    }

    func testStepsRunOneAtATimeSoTheLastReadIsWhatStays() async {
        let keeper = PairingKeeper(store: MemoryTokens())
        let vault = CountingVault()
        let sync = PairingSync(keeper: keeper) { vault.next() }
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 { group.addTask { await sync.keep() } }
        }
        XCTAssertEqual(keeper.kept, Data([50]))
    }

    func testAPairingThatCannotBeReadLeavesTheKeptOne() async {
        let keeper = PairingKeeper(store: MemoryTokens())
        keeper.keep(Data([7]))
        struct Locked: Error {}
        let sync = PairingSync(keeper: keeper) { throw Locked() }
        await sync.keep()
        XCTAssertEqual(keeper.kept, Data([7]))
    }

    func testTheTimerKeepsUntilStopped() async throws {
        let keeper = PairingKeeper(store: MemoryTokens())
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

/// Tokens in memory that count their writes.
private final class CountingTokens: TokenStore, @unchecked Sendable {
    private let inner = MemoryTokens()
    private(set) var writes = 0

    func token(for account: String) -> String? { inner.token(for: account) }

    @discardableResult
    func set(_ token: String?, for account: String) -> Bool {
        writes += 1
        return inner.set(token, for: account)
    }
}
