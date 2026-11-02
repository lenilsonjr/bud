REVIEW round 1
Reviewed: crew/BUD-68 against develop
What this does: `bud-ffi` now exports a `PeerNode` with start and stop, ticket string and QR rows, accept ticket, peers with `last_seen`, forget peer, sync now and a sync state. `bud-core` gains `peer_seen` tracking, `Node::forget_peer`, `Node::state` and `Vault::pending_changes`. BudKit gains a pure `VaultPaths` type that gives the vault and index folders per platform and says whether a tvOS launch with an empty vault should fetch from a peer.
Ticket check:
- Export start/stop, relay setting (default, custom URL, off): met.
- Ticket string and QR rows: met.
- Accept a ticket, list peers with last seen, forget a peer, sync now: met.
- Sync state (idle, connected peer count, pending changes): met.
- Every error stays a `VaultError` with the core's message: met. The `PeerNode` calls convert through the existing error path, and a closed node returns `Invalid`.
- `VaultPaths` in BudKit, Linux-pure: met. Both folders sit under Caches on tvOS, and the fetch rule is tvOS with an empty vault only.
- No views, and no changes to `scripts/`, `project.yml` or the Xcode targets: met. The diff touches none of them.
- Beyond the ticket: the `with_addresses` flag on `ticket` and `ticket_qr`. It is reasonable, since loopback with the relay off needs addresses.

Tests:
- I did not run the suite, as instructed. The host's checks on `74ccf37` passed (5 checks), covering the iOS, macOS, tvOS and gate checks the repository requires. No SwiftUI file is touched.
- The builder reports `core/bud-ffi/tests/peer.rs` (seven tests) and `Tests/BudKitTests/VaultPathsTests.swift` (five tests), with all five gate steps green.
- From the diff, the tests cover each new export. Nothing covers `stop()` while a `sync_now` is in flight.

Findings:
1. core/bud-core/src/peer.rs:608 question: `serve` calls `remember_peer` for any peer that proves it holds the vault key. A peer you forgot with `forget_peer` is re-added the next time it dials in, and `reached` then counts it as connected. Is that intended? If forget should stick, it needs a block list. The `peer_seen` row is written only through `reached`, so it does not outlive a forget except by this path.
2. core/bud-core/src/peer.rs:785 nit: `state()` calls `rescan()` on every poll and takes the vault lock to do it. A UI that polls often will rescan the folder each time. Fine for now, but worth a note for the screens that follow.
3. core/bud-ffi/src/lib.rs:244 nit: `stop()` holds the node mutex while it drops the node. If a `sync_now` is running on another thread, `stop` blocks until the sync returns, and the same applies to every other call on that node. This is acceptable, but unstated in the docs.
4. core/bud-core/src/sync.rs:366 nit: `pending_changes` treats an unreadable file as an empty string through `unwrap_or_default`, so it may count it as pending. This is harmless.

verdict: approved
