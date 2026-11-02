BUILD round 1

Ticket:
- `protocol Vault` in BudKit, pure Swift: **met**. It has `snapshot`, `create`, `setBody`, `setState`, `rename`, `move`, `trash`, `restore`, `emptyTrash`, `deleteForever`, `search`, `today`, `counts`, `nextStep` and `watch`, all async, in `Sources/BudKit/Vault.swift`.
  - I added `setWhen` and `setDue`. The store has them today and the protocol would lose them otherwise.
  - `setState` takes an optional state, so nil makes a bud a note.
  - `create` takes a `preferredPath`, so the store can keep the id it showed optimistically. A vault that names its own buds may ignore it.
- `BudRecord`, `RowRecord`, `HitRecord` and `CountsRecord` mirror the fields in `core/bud-ffi/src/lib.rs`: **partial**. `when`, `due` and `created` are `Date?`, not strings, so a round trip through the in-memory tree loses nothing. The Rust adapter will have to convert the day strings.
- `Bud` and `Tree` gain what they lack: **met**. `Bud` already had `when`, `due`, `pinned`, `created` and `source`, so only the others were added.
  - New: `Bud.path` and `Bud.id(forPath:)`.
  - New: `Tree.path(of:)`, `Tree.place(of:)`, `Tree.records()` and `Tree(records:)`.
  - `Tree.add` and `Tree.capture` take an optional `id`.
- `MemoryVault: Vault` over `Tree`: **met**. It is an actor with an optional JSON file, and `externalChange` stands in for a change made outside the app.
- `BudStore` takes a `Vault`: **met in code, not compiled or run here.** `BudStore` sits behind `#if canImport(SwiftUI)`, so neither it nor its tests were compiled here. The macOS CI on the pull request is the first real check of that file, and the same goes for `Tests/BudKitTests/StoreVaultTests.swift`.
  - `init(vault:tree:)` loads the snapshot, keeps `center` while its bud exists, and reloads on `watch` callbacks.
  - Every mutation changes the local tree at once, so the sync API, the return values and the toasts behave as before.
  - It then writes to the vault in order, and reloads when none are pending. A snapshot taken before a later local change is dropped.
  - `settle()` and `reload()` are public so tests can await them.
  - Undo goes through the vault: plant and capture undo is trash then delete forever; move, close and trash undo write the reverse change.
- `BudStore(fileURL:)` keeps working: **met in code, not compiled or run here.** It wraps a `MemoryVault` that reads and writes the same JSON file.
- Existing tests and snapshot pictures keep passing: **partial**.
  - All 100 existing and new Linux tests pass.
  - The SwiftUI-only store tests and the snapshot pictures cannot run here.
  - I did not change any existing test or weaken any expectation. The first picture is built from a tree that has been through the records round trip. Sibling `order` values are renumbered, which should not change any layout.
- No change to the App target, `project.yml`, `scripts/` or the Rust crates: **met**.

Changed:
- `Sources/BudKit/Vault.swift` (new)
- `Sources/BudKit/MemoryVault.swift` (new)
- `Sources/BudKit/TreeRecords.swift` (new)
- `Sources/BudKit/Tree.swift`
- `Sources/BudKit/BudStore.swift`
- `Tests/BudKitTests/VaultTests.swift` (new)
- `Tests/BudKitTests/StoreVaultTests.swift` (new)

Tests:
- `VaultTests` has 12 tests that run on Linux:
  - the seed round trip and its second trip;
  - record place, kind and parent, and parents coming before children;
  - create, edit, tick, move, trash and restore;
  - trashing a whole branch and restoring it as it was;
  - delete forever and empty trash;
  - a refused move, an unknown path, and the queries (`counts`, `search`, `today`, `nextStep`);
  - `watch` and its cancel, file persistence, and stable ids for paths that are not ids.
- `StoreVaultTests` has 10 tests, SwiftUI-only. They cover load, add, capture, edit, tick and pin, move and its undo, trash, restore and undo, delete forever and empty trash, a `watch` callback reloading the tree, the center staying put, and the file store.
- Gate: `swift build` passed. `swift test` ran 100 tests with 0 failures. `cargo fmt --all --check`, `cargo clippy --all-targets -- -D warnings` and `cargo test --workspace` all passed.

Verify:
- Run `swift test` and look at `VaultTests`.
- Read the macOS and iOS CI results on the pull request, which compile `BudStore` and run `StoreVaultTests` and the snapshot pictures.
- By hand, launch the app and plant, tick, move and trash a bud, then undo each. The behaviour and toasts should match the previous build, and `buds.json` should still be written.
