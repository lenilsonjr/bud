BUILD round 1
Ticket:
- Carry unknown frontmatter keys in the document as an ordered map, so the receiving file holds them in the sender's order: met. Each unknown key is kept in the document as the lines the sender wrote, together with the order of all the keys in the block. A file made on the other side gets the same block.
- Remove the `#[ignore]` from `every_frontmatter_key_reaches_the_other_vault` and restore the two loosened comparisons to full-file equality: met. The ignore is gone. The `same()` helper is deleted, and both comparisons in `an_edit_on_one_vault_appears_in_the_other` are full-file equality again.
- Do not change how a file with only the six keys is written: met. With no unknown keys, `write_layout` returns the text unchanged. A unit test covers it, and the existing frontmatter and sync tests still pass.

Documents made before this change do not track unknown keys. The first sync reads them from the file and never deletes them, so existing `tags` are safe.

Changed:
- `core/bud-core/src/frontmatter.rs`: `Layout`, `layout()` and `write_layout()`, plus unit tests.
- `core/bud-core/src/sync.rs`: the document holds the unknown keys and their order, and sync writes them back to the file.
- `core/bud-core/src/lib.rs`: `set_properties` now calls an internal `write_properties` that can also apply a layout. Exports for the new items.
- `core/bud-core/src/peer.rs`: module comment updated.
- `core/bud-core/tests/peer.rs`: ignore removed, comparisons restored, new test `unknown_keys_arrive_in_the_senders_order`.

Tests:
- New frontmatter unit tests:
  - the unknown keys and the key order are read;
  - a layout is written in its order and is stable on a second write;
  - a layout replaces and removes unknown keys only;
  - a file with only the six keys is left alone;
  - a layout makes a block when the file has none.
- New peer test `unknown_keys_arrive_in_the_senders_order`: it uses a block with interleaved unknown and known keys, a list value and a comment. The copy on the second vault is identical to the sender's, and an edit to an unknown key made there comes back to the first vault.
- `swift build` passes, with 0 SwiftUI-free targets failing.
- `swift test` passes: 83 tests, 0 failures.
- `cargo fmt --all --check` is clean.
- `cargo clippy --all-targets -- -D warnings` is clean.
- `cargo test --workspace` passes, including `every_frontmatter_key_reaches_the_other_vault`, with no ignored test in `tests/peer.rs`.

Verify: from the repository root, run `cargo test -p bud-core --test peer`. All 14 tests pass with none ignored. For a manual check, pair two vaults and add `tags: [x]` to a note's frontmatter on one. After a sync the other vault's file is byte-identical, including the key order.
