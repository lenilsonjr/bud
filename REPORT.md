I applied finding 1 and the gate passes, but the change is not committed. `git add` was denied again because the box has no decision channel for version-control calls. The change sits uncommitted in `core/bud-core/src/frontmatter.rs`. The suggested commit subject is "🐛 Keep known keys that already read right".

```
BUILD round 2
Applied:
- Finding 1 (known keys rewritten when already right): `edit_block` in core/bud-core/src/frontmatter.rs now gathers each known key's line and its indented continuation. It parses that text with the same `parse` as reading. If the result already equals the wanted value, the original text is kept untouched, so quotes, trailing comments, `pinned: yes` and quoted dates survive a change to a different key. Only a differing key is rewritten, and a `None` still removes it. The new test `known_keys_that_already_read_right_keep_their_own_text` covers it:
  - It sets `state` on a block with `source: "phone"`, `state: open # check`, `pinned: yes`, `when: '2026-11-02'` and a `due` with an indented comment under it. Only the state line changes.
  - It then sets the state back to `open`, and the text comes out byte for byte the same as the input.
Declined:
- Finding 1, keeping a trailing comment when a key is rewritten: a rewritten key now loses its trailing comment (`state: open # check` becomes `state: done`). That is the only text of the user's that a changed key drops. Splitting a value from its comment safely needs a YAML-aware scan for quoted `#`, which is more machinery than this ticket asks for, and the reviewer said "consider".
- Finding 2 (no sync before the rename): the ticket asks for write then rename, which is what is done. A sync is hardening beyond the ticket.
- Finding 3 (invalid UTF-8): a file that is not valid UTF-8 is refused with an `Io` error and nothing is written. The reviewer asked only whether that is intended, and it is, so there is no change.
Tests:
- `cargo fmt --all --check`: clean.
- `cargo clippy --all-targets -- -D warnings`: clean.
- `cargo test --workspace`: 30 passed (16 unit, 10 scan, 4 set_properties).
- `swift build`: passed.
- `swift test`: 9 passed.
```
