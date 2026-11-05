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
    private let service = "bud.sources"

    public init() {}

    public func token(for account: String) -> String? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let data = found as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public func set(_ token: String?, for account: String) -> Bool {
        SecItemDelete(base(account) as CFDictionary)
        guard let token else { return true }
        var item = base(account)
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
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
