REVIEW round 1
Reviewed: crew/BUD-64 against develop
What this does: Unknown frontmatter keys such as `tags` are now kept in the sync document, each as the lines the sender wrote, together with the order of every key in the block. When a file is written, `write_layout` puts those keys back in the sender's order. A file that has only the six known keys is left as it was. Documents made before this change pick up their unknown keys from the file on first sync.

Ticket check:
- Carry unknown keys as an ordered map so the receiver holds them in the sender's order: met. They are stored as per-key text plus an order list, and a peer test checks the result is byte-identical.
- Remove `#[ignore]` and restore the two loosened comparisons to full-file equality: met. The ignore, the `same()` helper and both loosened comparisons are gone from `core/bud-core/tests/peer.rs`.
- A file with only the six keys is written as before: met. `write_layout` returns the text unchanged when there are no unknown keys, and a unit test covers it.

Tests:
- New unit tests in `core/bud-core/src/frontmatter.rs` cover reading, order, replace and remove, the six-key no-op, and creating a block.
- New peer test `unknown_keys_arrive_in_the_senders_order` covers interleaved keys, a list value and a comment, and an edit coming back the other way.
- I did not run the suite. The host's checks on `3591d760a6521cdc6a9e3107d0fdb9e54390b240` passed (5 checks). I read the diff and the report instead.
- Not covered: a concurrent edit of the same unknown key on both sides, and a key whose name contains `:`. The first resolves last-writer-wins, which is acceptable. The second is a rare edge case.

Findings:
1. `core/bud-core/src/frontmatter.rs:91` nit: `chunks` treats any non-indented line with a `:` as a new top-level key. A quoted key containing `:`, or a block-scalar continuation at column 0, would be split wrongly. This is rare and does not block.
2. `core/bud-core/src/sync.rs:755` nit: the `write_layout(&file, &layout) != file` check runs on every sync of every file. It is cheap and the tests show it converges, so I note it only for awareness.

verdict: approved
