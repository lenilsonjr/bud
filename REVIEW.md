REVIEW round 1
Reviewed: crew/BUD-39 against develop
What this does: Adds a `sync` module to `bud-core`. Each bud gets a Loro document stored in a `docs` table (path, id, bytes, known text), plus a tree document keyed by bud identity for renames, moves and trashing. An outside edit of a file is diffed into text operations and map sets. A merged document is written back through `set_properties` and `set_body`, and nothing is written when the document and file agree.
Ticket check:
- `docs` table and `sync` module: met.
- Document per bud on first scan, updated from the file: partial. A document is made and updated, but the diff is against the document's text, not the known text (finding 1).
- Merged state written back through the shared writers, known text updated: met.
- Moves, renames and trashing as tree operations keyed by bud identity: partial. They are implemented and the same-bud-move test converges. Identities are random per replica, so replicas converge only after `adopt_doc` (finding 2).
- No write when document equals file: met.
Tests: CI was not run here. The host reported its 5 checks passed on the head; I took that and did not rerun them. I ran the box gate myself from the repo root:
- `swift build`: complete.
- `swift test`: 42 passed.
- `cargo fmt --all --check`: clean.
- `cargo clippy --all-targets -- -D warnings`: clean.
- `cargo test --workspace`: all passed, including the 10 tests in `tests/sync.rs` and `the_vault_is_never_written`.

The diff touches no SwiftUI file. Gap: no test covers an outside edit that lands while the document holds remote changes the file does not have yet (finding 1).
Findings:
1. core/bud-core/src/sync.rs:155 bug: `absorb` diffs the document's current text and properties against the file, and never reads `known_text`. The ticket says to diff the old known text against the new file text. Failure path: replica A syncs, then someone edits the file outside. Before the next `sync()`, `merge_doc` imports B's edit into A's document and calls `sync_path`. There `file != known`, so `absorb(doc, file)` runs. It deletes B's inserted text, because the file lacks it, and drops any property B set. The merged edit is lost on both replicas. The fix is to turn the known-to-file difference into operations on the document, which keeps concurrent remote edits (or to apply the outside edit before importing). Add a test that makes an outside edit, then calls `merge_doc` before `sync`.
2. core/bud-core/src/sync.rs:463 design: the document id is `randomblob(16)`, so two replicas that scan the same vault get different ids for the same bud. The tree document is keyed by those ids, so "two replicas converge" only holds after the manual `adopt_doc` handoff, as the report admits. Consider a deterministic id, or state the handoff as a contract. This alone does not block.
3. core/bud-core/src/sync.rs:290 question: a file renamed or moved outside the app shows up as a removed path plus a new path. The stale branch deletes the old doc and its tree node, and a new identity is made, losing history and the identity that other replicas use. Is that intended for this ticket?
verdict: changes requested
