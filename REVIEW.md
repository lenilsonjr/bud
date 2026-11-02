REVIEW round 1
Reviewed: crew/BUD-70 against develop
What this does: Issued tickets now carry an `issued` timestamp. `ticket()` drops tickets older than ten minutes before it inserts, and a hello with an expired id is refused like a never-issued one. When a key hand-over gets no confirmation, the rotation probes the peer once over a session sealed with the new key. A peer is listed in `RotateReport.missed` only if that probe also fails. Missed peers are stored in a new `peer_missed` table and exposed as `missed` on `PeerInfo` and on the FFI `PeerRecord`.

Ticket check:
- Ticket lifetime (timestamp, prune on issue, refuse expired on redeem): met.
- `missed` means holds the old key (probe retry): met.
- Missed peers marked in `peers`: met. The mark clears on a working session, on the next rotation, and on forget.
- Loopback tests for expiry and for the dropped acknowledgement: met.
- Table does not grow without bound: met by the code, not tested directly.

Tests:
- The new tests in `core/bud-core/tests/peer.rs` are `an_expired_ticket_is_refused_and_a_fresh_one_works`, `a_lost_acknowledgement_does_not_make_a_peer_missed` and `a_peer_that_kept_the_old_key_is_missed_and_marked`. They cover both verification cases in the ticket.
- The lost-acknowledgement test checks that the peer is not listed and that its key matches. The kept-old-key test checks the report and the `missed` mark.
- I did not run the gate. The host's checks on the head, 9cdf2aca86c6fbfb858e90e54390a6c04448ebb4, passed (5 checks), and the instruction was to read the diff and the report instead.
- No SwiftUI file is touched. Nothing in the repo constructs `PeerRecord`, so the new field breaks no other code.
- There is no test that the table stays small after repeated `ticket()` calls. The builder says so too. It is a gap, not a blocker.

Findings:
1. `core/bud-core/src/peer.rs:16` nit: the edited module doc line runs well past the wrap of the lines around it. Re-wrap it.
2. `core/bud-core/src/peer.rs` (`rotate`, `holds_key`) nit: a peer that gets the new key but whose connection fails both times is listed as missed even though it holds the new key. The next successful session clears the mark, so this is acceptable and matches the ticket's "retries once".
3. `core/bud-core/tests/peer.rs` nit: add an assertion that `tickets_issued` is pruned on issue, for example by counting rows through a test hook. The ticket's first criterion is about table growth, and nothing checks it directly.

verdict: approved
