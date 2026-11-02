BUILD round 1
Ticket:
- **bud-ffi exports: met.**
  - `start_node(vault, RelaySetting)` starts a node. `RelaySetting` is `Default`, `Custom { url }` or `Off`. `PeerNode.stop()` stops it, and every later call on a stopped node returns an error.
  - `ticket(with_addresses)` returns the ticket string. `ticket_qr(with_addresses)` returns the QR modules as rows of booleans.
  - `accept_ticket`, `peers` (each with `last_seen`), `forget_peer` and `sync_now` are exported. `sync_now` returns a `SyncSummary` of counts.
  - `state()` returns a `SyncState` with `idle`, `connected_peers` and `pending_changes`.
- **Errors as `VaultError`: met.** Every export returns `VaultError` with the core's message. A closed node and an unknown peer are `Invalid`. A repeated ticket is `Exists`.
- **Swift paths type in BudKit: met.** `VaultPaths` takes a platform and a base folder and returns `vaultFolder`, `indexFolder` and `indexFile`. On tvOS both folders sit under `Library/Caches/Bud`. `fetchesFromPeer(vaultFolderIsEmpty:)` is true only on tvOS with an empty vault folder.
- **No views, and no changes to `scripts/`, `project.yml` or the Xcode targets: met.**

Choices the ticket left open:
- **Base folder:** I took it to be the app's container, so paths are `Documents/Bud` and `Library/Application Support/Bud` on macOS and iOS. Say so if the app should pass a different base.
- **Connected peers:** a peer counts as connected after a session with it works. It drops out when a dial to it fails, or when you forget it. A peer that only dials this node stays counted until our own dial to it fails.
- **Pending changes:** the number of Markdown files that differ from what their document last knew, or have no document yet.
- **Ticket addresses:** with the relay off, a ticket only works over loopback if it carries addresses, so `ticket` and `ticket_qr` take `with_addresses`.

Changed:
- `core/bud-core/src/schema.sql`: new `peer_seen` table, so existing indexes need no migration.
- `core/bud-core/src/peer.rs`: `PeerInfo.last_seen`, `NodeState`, `Node::forget_peer`, `Node::state`, and tracking of running sessions and reached peers.
- `core/bud-core/src/sync.rs`: `Vault::pending_changes`.
- `core/bud-core/src/lib.rs`: exports `NodeState`.
- `core/bud-ffi/src/lib.rs`: the new exports. The vault now sits behind an `Arc<Mutex<…>>` so a node can share it.
- `core/bud-ffi/tests/peer.rs`: new tests.
- `Sources/BudKit/VaultPaths.swift`: new.
- `Tests/BudKitTests/VaultPathsTests.swift`: new.

Tests: all five gate steps pass.
- **`core/bud-ffi/tests/peer.rs`:** seven tests, each with two temporary vaults over loopback and the relay off. They cover:
  - the ticket string and the QR rows
  - each relay setting, including a bad custom URL
  - accepting a ticket, listing the peer, and `last_seen` being unset before the first sync and set after it
  - a sync that carries notes across
  - `state()` for idle, connected peers and pending changes
  - `forget_peer`, including an unknown peer
  - error messages and variants
  - a stopped node refusing calls
- **`Tests/BudKitTests/VaultPathsTests.swift`:** five tests covering macOS, iOS and tvOS inputs, the vault and index never sharing a folder, and the fetch rule.
- **Gate results:**
  - `swift build`: ok
  - `swift test`: 88 tests, 0 failures
  - `cargo fmt --all --check`: ok
  - `cargo clippy --all-targets -- -D warnings`: ok
  - `cargo test --workspace`: ok
- **Not run:** the app targets compile on CI only.
- **No test weakened.**

Verify:
- Run `cargo test -p bud-ffi --test peer` and `swift test --filter VaultPathsTests` from the repository root.
- To see pairing by hand, read `accepting_a_ticket_lists_the_peer_and_sync_now_moves_the_notes` and `the_state_counts_connected_peers_and_pending_changes` in `core/bud-ffi/tests/peer.rs`. They run the whole flow through the same calls Swift will make.
