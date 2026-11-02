import Foundation

/// The platforms the app runs on, as far as where a vault lives.
public enum VaultPlatform: Sendable, Equatable {
    case macOS
    case iOS
    case tvOS
}

/// Where a vault and its index live on one platform, under the app's base folder (its container).
///
/// On the Mac and iPhone the vault is a folder of Markdown files in Documents and the index sits
/// beside the app's other support files. The Apple TV keeps nothing it cannot fetch again: both
/// live under Caches, and a launch that finds the vault empty asks a peer for it.
public struct VaultPaths: Sendable, Equatable {
    public let platform: VaultPlatform
    public let base: URL

    public init(platform: VaultPlatform, base: URL) {
        self.platform = platform
        self.base = base
    }

    /// The folder of Markdown files.
    public var vaultFolder: URL {
        switch platform {
        case .macOS, .iOS:
            return base.appendingPathComponent("Documents").appendingPathComponent("Bud")
        case .tvOS:
            return cachesFolder.appendingPathComponent("Vault")
        }
    }

    /// The folder for what belongs to this device and not to the vault: the index, the node key
    /// and the peers.
    public var indexFolder: URL {
        switch platform {
        case .macOS, .iOS:
            return base.appendingPathComponent("Library").appendingPathComponent("Application Support")
                .appendingPathComponent("Bud")
        case .tvOS:
            return cachesFolder.appendingPathComponent("Index")
        }
    }

    /// The index database inside `indexFolder`.
    public var indexFile: URL {
        indexFolder.appendingPathComponent("index.db")
    }

    /// Whether a launch should fetch the vault from a peer before it shows cards: only where the
    /// vault is a cache, and only while its folder is empty.
    public func fetchesFromPeer(vaultFolderIsEmpty: Bool) -> Bool {
        platform == .tvOS && vaultFolderIsEmpty
    }

    private var cachesFolder: URL {
        base.appendingPathComponent("Library").appendingPathComponent("Caches").appendingPathComponent("Bud")
    }
}
