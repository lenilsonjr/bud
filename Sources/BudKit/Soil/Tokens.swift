import Foundation
#if canImport(Security)
import Security
#endif

/// Where a device keeps the tokens that read its sources. Never the vault: a token stays on the
/// device that was signed in, and another device sees the account locked.
public protocol TokenStore: Sendable {
    func token(for account: String) -> String?
    /// Nil forgets it. False when the token could not be kept.
    @discardableResult
    func set(_ token: String?, for account: String) -> Bool
}

/// Tokens in memory, for tests, previews and Linux.
public final class MemoryTokens: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [String: String]

    public init(_ tokens: [String: String] = [:]) { self.tokens = tokens }

    public func token(for account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return tokens[account]
    }

    @discardableResult
    public func set(_ token: String?, for account: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        tokens[account] = token
        return true
    }
}

#if canImport(Security)
/// Tokens in this device's Keychain, readable after the first unlock and never synced to iCloud.
public struct KeychainTokens: TokenStore {
    private let service: String

    /// The tokens of the sources, or another kind of secret under its own service.
    public init(service: String = "bud.sources") {
        self.service = service
    }

    public func token(for account: String) -> String? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let data = found as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Replaces the token in place, so a write that fails leaves the one before; adds it only
    /// when there was none.
    @discardableResult
    public func set(_ token: String?, for account: String) -> Bool {
        guard let token else {
            let status = SecItemDelete(base(account) as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        // Only the value changes in place; how the item may be read is set once, when it is added.
        let value: [String: Any] = [kSecValueData as String: Data(token.utf8)]
        let updated = SecItemUpdate(base(account) as CFDictionary, value as CFDictionary)
        guard updated == errSecItemNotFound else { return updated == errSecSuccess }
        let item = base(account).merging(value) { _, new in new }
            .merging([kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]) { _, new in new }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private func base(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }
}
#endif
