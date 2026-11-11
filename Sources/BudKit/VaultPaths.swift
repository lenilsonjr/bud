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
/// live under Caches, and a launch that finds them cleared asks a peer for the vault.
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

    /// The node's key inside `indexFolder`, beside the index, under `name`: the core names it,
    /// and the app hands that name on from the bindings.
    public func nodeKeyFile(named name: String) -> URL {
        indexFolder.appendingPathComponent(name)
    }

    /// Whether a launch should fetch the vault from a peer before it shows cards: only where the
    /// vault is a cache, and only when the cache was cleared. The system clears Caches as a
    /// whole, so the index and the node key, under the core's `nodeKey` name, both gone is the
    /// sign; an empty folder beside an index is a vault that is empty, or whose deletions have
    /// not synced yet, and opens as it is.
    public func fetchesFromPeer(nodeKey: String, _ files: FileManager = .default) -> Bool {
        platform == .tvOS && !files.fileExists(atPath: indexFile.path)
            && !files.fileExists(atPath: nodeKeyFile(named: nodeKey).path)
    }

    /// Clears what is left in the vault folder, keeping the folder: on the Apple TV, when the
    /// index is gone and the vault comes back from the peers, which hold the truth. Files left
    /// over would otherwise be read as new buds beside theirs.
    public func emptyVaultFolder(_ files: FileManager = .default) {
        guard platform == .tvOS else { return }
        for name in (try? files.contentsOfDirectory(atPath: vaultFolder.path)) ?? [] {
            try? files.removeItem(at: vaultFolder.appendingPathComponent(name))
        }
    }

    private var cachesFolder: URL {
        base.appendingPathComponent("Library").appendingPathComponent("Caches").appendingPathComponent("Bud")
    }
}
