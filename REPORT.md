BUILD round 1

Ticket:
- Forget a peer and refuse its node id afterwards, even when it proves the key: met. `forget_peer` now also records the node as refused. The node is turned away before its first message is read. `Node::allow_peer` lifts that. Accepting a ticket from a vault this one removed earlier also lifts it.
- Rotate the vault key on request: met.
  - `Node::rotate_key` makes a new key and hands it to each remaining peer over a session sealed with the old key. The peer accepts it only from a node it already knows. Then the maker switches keys and voids every ticket it issued.
  - It returns a `RotateReport` with the number of peers reached and the ids it could not reach. A peer it missed keeps the old key and is turned away.
  - The Rust-to-Swift bindings (`bud-ffi`) get `rotate_key`, which returns the ids of the peers missed. The SwiftUI side is not wired.
- Ticket is one-shot on the maker's side: met.
  - Each ticket now carries a random `id`, and every call to `ticket()` issues a fresh one. The maker records issued ids.
  - A node it does not know must present an issued id in its first message. The id is spent on first use.
  - A ticket that was never issued or is redeemed twice is refused.
  - The accepting side holds the id until its first session works, then drops it.

Changed:
- `core/bud-core/src/peer.rs`
- `core/bud-core/src/schema.sql` (three new tables, all `IF NOT EXISTS`, so no version bump)
- `core/bud-core/src/lib.rs` (exports `RotateReport`)
- `core/bud-core/tests/peer.rs`
- `core/bud-ffi/src/lib.rs`

Wire change: the `Hello` message now carries the ticket id, and there is a new `Rotate` message. Both ends must run this version, and the `Ticket` string gained a field, so tickets made before this change no longer parse.

Tests: the new tests are in `core/bud-core/tests/peer.rs`, over loopback with the relay off:
- `a_removed_peer_cannot_sync_even_with_the_key`: a removed peer that still holds the key cannot sync and is not learned again.
- `a_removed_peer_is_paired_again_with_a_fresh_ticket`: the removed node stays refused until `allow_peer`, then pairs with a fresh ticket.
- `rotating_the_key_moves_the_remaining_peers_and_turns_the_old_key_away`: the kept peer gets the new key and keeps syncing. The removed peer on the old key is turned away. A ticket made before the rotation pairs nothing.
- `a_ticket_redeemed_twice_is_refused_the_second_time`: a second node redeeming the same ticket is refused, and a fresh ticket works.
- `a_ticket_that_was_never_issued_pairs_nothing`: a made-up ticket id is refused.

I added an `id` to the existing ticket literals in that file. No expectation was weakened.

Gate, each step run from the repository root:
- `swift build`: passed.
- `swift test`: 88 tests passed.
- `cargo fmt --all --check`: clean after I ran `cargo fmt --all`, which reformatted two spots in `peer.rs`.
- `cargo clippy --all-targets -- -D warnings`: clean.
- `cargo test --workspace`: all passed, including 19 peer tests.

Verify: run `cargo test -p bud-core --test peer` from the root and read the five tests above. By hand, two vaults pair with a ticket and sync. Removing one from the other makes the removed one fail `sync_now`. After `rotate_key`, a vault left on the old key fails `sync_now`, and the kept peer syncs.
