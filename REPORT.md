BUILD round 1
Ticket:
- Issued tickets expire: met. `tickets_issued` now records when each ticket was made. `ticket()` drops tickets older than ten minutes before it inserts. A hello that presents an expired id is refused like a never-issued one. A refreshed QR no longer grows the table without bound.
- `RotateReport.missed` means "holds the old key": met. A peer whose confirmation was lost is asked once more over a session sealed with the new key. It counts as reached if it answers, and is listed as missed only if that also fails.
- Missed peers are marked in `peers`: met. `PeerInfo.missed` and the FFI `PeerRecord.missed` carry the mark. It clears when a session with the peer works again, when a later rotation runs, or when the peer is forgotten.

Changed:
- `core/bud-core/src/peer.rs`
- `core/bud-core/src/schema.sql`
- `core/bud-core/src/lib.rs`
- `core/bud-core/tests/peer.rs`
- `core/bud-ffi/src/lib.rs`

Schema changes:
- `tickets_issued` gains an `issued` column.
- A new `peer_missed` table holds the marks.
- `SCHEMA_VERSION` goes from 2 to 3, and an older `tickets_issued` table is dropped on open. Nothing durable is lost, because tickets are short-lived.

Two `#[doc(hidden)]` `Node` methods exist only so loopback tests can run: `set_ticket_lifetime` and `drop_next_key_acks`. The first lets the expiry test use a short window. The second makes a peer take the new key and withhold its confirmation.

Tests:
- `an_expired_ticket_is_refused_and_a_fresh_one_works`
- `a_lost_acknowledgement_does_not_make_a_peer_missed`
- `a_peer_that_kept_the_old_key_is_missed_and_marked`

All three are in `core/bud-core/tests/peer.rs`, and no existing expectation was weakened.

There is no direct test that the issued-tickets table stays small after many refreshes. The loopback test only checks that an expired ticket is refused and a fresh one pairs.

Gate, run from the repo root:
- `swift build`: passed.
- `swift test`: passed, 100 tests.
- `cargo fmt --all --check`: passed after I ran `cargo fmt --all`, which only re-wrapped one assertion in the new test.
- `cargo clippy --all-targets -- -D warnings`: clean.
- `cargo test --workspace`: all passed, including 22 tests in `core/bud-core/tests/peer.rs`.

The app targets compile only on CI after the push; I did not touch any SwiftUI file.

Verify:
- Run `cargo test --workspace -p bud-core --test peer`.
- To check expiry by hand, make a ticket, wait more than ten minutes, and accept it on another vault. The sync is refused.
- To check the missed mark by hand, rotate the key while one peer has already removed this vault. That peer shows in the report's `missed` list and in `peers` with `missed` true. A peer that took the key but lost its confirmation is not listed.
