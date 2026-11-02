BUILD round 1
Ticket:
- `sync` module with a `docs` table: met. `core/bud-core/src/sync.rs` and `core/bud-core/src/schema.sql`. The table holds path, document id, document bytes and the last known file text. A second table, `tree_doc`, holds the tree document. Neither is dropped on a schema change, because the bytes carry history.
- A document for every bud on the first scan, updated from the file: met. `Vault::sync()` makes a document per bud. A file that differs from the known text is diffed, and the difference becomes text operations on the body. Changed properties become map sets. Documents are Loro CRDT documents, so the crate now depends on `loro` and `diff`.
- Merged state written back through the same writer, known text updated: met. `sync()` and `merge_doc()` write back through `set_properties` and `set_body`, the writers every other edit uses. The known text is updated after the write.
- Moves, renames and trashing as tree operations keyed by bud identity: met. `sync()` records them in the tree document. `merge_tree()` imports another replica's tree and renames, moves, trashes or restores files until the folder matches it. Two replicas that move the same bud converge on one place. `relocate` in `core/bud-core/src/edit.rs` now keeps `docs.path` in step.
- No file written when the document equals the file: met. Nothing is written when the document and the file agree. The tests check this by comparing the file's bytes and modification time.
- Two limits:
  - Bootstrapping a second replica uses `adopt_doc`, which takes the other replica's document under that replica's identity.
  - Two replicas that each scan the same vault independently would otherwise get different identities for the same bud.

Changed: `core/bud-core/Cargo.toml`, `Cargo.lock`, `core/bud-core/src/lib.rs`, `core/bud-core/src/edit.rs`, `core/bud-core/src/schema.sql`, `core/bud-core/src/sync.rs` (new), `core/bud-core/tests/sync.rs` (new)

Tests: `core/bud-core/tests/sync.rs` has ten tests, all passing.
- A document is made for each of the 13 fixture buds, and a second sync does nothing.
- Scanning and syncing the fixture vault leaves it byte-identical.
- An outside edit gives operations and no file write: the bytes and mtime are unchanged and the body and properties land in the document.
- Two documents edited apart merge to one text with both edits, in both directions, and a repeat merge writes nothing.
- A property set on one replica reaches the other's file with only that key line changed.
- A rename on one replica and an edit on the other end with the edited text under the new name on both.
- A move of the same bud on both replicas converges.
- Trashing and restoring travel through the tree.
- A tree merge that matches the folder writes nothing.
- A removed file leaves no document.

The existing `the_vault_is_never_written` test in `core/bud-core/tests/scan.rs` still passes. No expectation was weakened.

Gate, from the repo root:
- `swift build`: passed.
- `swift test`: 42 tests passed.
- `cargo fmt --all --check`: clean.
- `cargo clippy --all-targets -- -D warnings`: clean.
- `cargo test --workspace`: all passed.

Verify: From the repo root, run `cargo test -p bud-core --test sync`. To see an outside edit by hand, open a vault, call `rescan()` then `sync()`, edit a file in an editor, and call `rescan()` and `sync()` again. The report shows `updated: 1`, `ops > 0` and `written: 0`, and the file is untouched.
