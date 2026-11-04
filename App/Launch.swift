import Foundation
import BudKit

/// Where the app's store comes from: the vault folder on disk, through the Rust core.
@MainActor
enum Launch {
    static var platform: VaultPlatform {
        #if os(macOS)
        return .macOS
        #elseif os(tvOS)
        return .tvOS
        #else
        return .iOS
        #endif
    }

    /// The store over this device's vault. The first launch on a device that kept its buds in
    /// the old JSON file plants them in the empty vault and sets the file aside. A vault that will
    /// not open leaves the app on the JSON file, as before.
    static func store() -> BudStore {
        let paths = VaultPaths(platform: platform, base: URL(fileURLWithPath: NSHomeDirectory()))
        guard let vault = try? RustVault(paths: paths) else { return BudStore() }
        if let file = BudStore.defaultFile, let tree = old(file), (try? vault.core.snapshot().isEmpty) == true {
            do {
                try vault.plant(tree.records())
                try FileManager.default.moveItem(at: file, to: file.deletingPathExtension().appendingPathExtension("imported.json"))
            } catch {
                NSLog("Bud: the old buds did not move into the vault: \(error)")
            }
        }
        return BudStore(vault: vault)
    }

    private static func old(_ file: URL) -> Tree? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Tree.self, from: data)
    }
}
