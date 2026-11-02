REVIEW round 1
Reviewed: crew/BUD-65 against develop
What this does: `forget_peer` now also records the node in a `peer_denied` table, and the answerer turns that node away before reading its first message. Each ticket carries a random id that the maker records and spends on first redemption. A node the maker does not know must present an unspent id in its Hello. `Node::rotate_key` makes a new key and sends it to each peer in a `Rotate` message sealed with the old key. A peer accepts it only from a node it already knows. The maker then switches keys and voids all of its issued tickets. `bud-ffi` gets `rotate_key`, which returns the ids of the peers it missed.

Ticket check:
- Forget a peer and refuse its node id even when it proves the key: met. The denial check in `peer.rs` runs before the key is used. `allow_peer`, or accepting a new ticket from the same vault, lifts the denial.
- Rotate the key, send it to the remaining peers over sealed sessions, and stop old tickets: met. `replace_key` clears `tickets_issued`. Old tickets also carry the old key, which the maker no longer accepts.
- One-shot ticket on the maker's side: met. `redeem_ticket` is a `DELETE` that must change exactly one row, so a second redemption or an invented id fails.
- Beyond the ticket: `allow_peer`, the `RotateReport` type, and an FFI `rotate_key`. All are small and reasonable. The SwiftUI side is not wired, which the ticket does not ask for.

Tests: `core/bud-core/tests/peer.rs` has five new loopback tests that map one-to-one to the three verification lines in the ticket (removed peer cannot sync, old key turned away after rotation, ticket redeemed twice refused), plus re-pairing and a never-issued ticket. The existing ticket literals only gained an `id`, and no expectation was weakened. I did not run the suite myself, as instructed. The host's checks on `ca5650ad4de9c12f0903cf3aaec0603f09b1cd2a` passed (5 checks), which covers the required iOS, macOS, tvOS and `gate` checks. The diff touches no SwiftUI file. Gaps: no test for a `Rotate` message from an unknown node, which the code refuses, and none for a peer that is unreachable during rotation.

Findings:
1. `core/bud-core/src/peer.rs` (`Shared::rotate`) design, nit: a peer that applied the new key but whose `Done` never reached the maker is reported in `missed`, even though it is actually on the new key. The maker switches keys regardless, so the report can be wrong in that direction. It is harmless to sync but misleading to the caller.
2. `core/bud-core/src/peer.rs` (`Vault::forget`) design, question: the denial is local to the vault that forgot the peer. Until the key is rotated, a removed device can still sync with any other peer that has not forgotten it. This fits the ticket, since rotation is the remedy, but is it intended that the UI will push rotation after every removal?
3. `core/bud-core/src/schema.sql` (`tickets_issued`) nit: every call to `ticket()` inserts a row, and rows leave only on redemption or rotation. Repeated QR refreshes will grow the table without bound, and an unredeemed ticket never expires.
4. `core/bud-core/src/peer.rs` (`Shared::rotate`) design, nit: peers that missed the rotation stay in `peers` on the maker with the old key, so every later session with them fails until they pair again. The report documents this, but nothing in the code marks those peers.

verdict: approved
