REVIEW round 2
Earlier findings:
1. Known keys rewritten when already right: addressed. `edit_block` now keeps the original text of a key and its indented continuation when it already parses to the wanted value. `known_keys_that_already_read_right_keep_their_own_text` covers quotes, a trailing comment, `pinned: yes`, a quoted date and an indented comment. It also checks that setting the state back gives the input byte for byte. The decline on keeping a trailing comment when a key itself changes is reasonable, and I accept it.
2. No sync before the rename: declined as a nit, and I accept the decline.
3. Invalid UTF-8 question: answered. A file that is not valid UTF-8 is refused with an `Io` error and nothing is written. No change is needed.

New: Nothing. The only change since the last review is in `core/bud-core/src/frontmatter.rs`. `edit_block` now reads a key's continuation lines before deciding whether to keep or rewrite it, and a repeated key is still dropped.

Tests: I ran the gate from `work`.
- `swift build`: passed.
- `swift test`: 9 passed.
- `cargo fmt --all --check`: clean.
- `cargo clippy --all-targets -- -D warnings`: clean.
- `cargo test --workspace`: 30 passed (16 unit, 10 scan, 4 set_properties).
- The host's checks on `d7a9d34` passed (4 checks). I did not re-run them.

verdict: approved
