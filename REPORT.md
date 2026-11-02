The code and tests are written and the gate passes. I could not commit: `git add` was denied because the box has no decision channel for version-control calls. I did not try another route. The changes sit uncommitted in `work` on `crew/BUD-14`: two modified files and one new test file.

```
BUILD round 1
Ticket:
- Properties parse and `frontmatter::write(text, &Properties) -> String`: met. An existing key is replaced in place, a new key is appended at the end of the block, and a `None` removes the key. A file with no block gets one only when something is set. Unit tests cover each case. A fixture with `tags`, `aliases` and a comment line survives byte for byte.
- `Vault::set_properties(path, &Properties)`: met. It writes `<name>.md.tmp` beside the file, renames it into place, and updates the index row. A folder-only bud gets `Name.md` created beside the folder first. The old folder row is dropped and the children's `parent` moves to the new file. The body is identical before and after, in the file and in the index. The index agrees with a rescan.
- Written formats: met. `state` is written as `open` or `done`, `when` and `due` as given (`YYYY-MM-DD`), `created` as given (RFC 3339), and `pinned` as `true` (absent when false). A snapshot test covers the written text. `Properties` still holds dates as strings, so the writer does not validate them. It writes what it is given.
- No reformatting outside the touched keys: met. Comments, quotes, indentation, unknown keys and CRLF line endings are kept. Values under a touched key that are indented lines go with it when it is replaced or removed. Free-text values such as `source` are quoted only when plain YAML would not read back the same.
- Not done: the commit. `git add` was denied by the box, so the branch has no new commit from this round.
Changed: core/bud-core/src/frontmatter.rs, core/bud-core/src/lib.rs, core/bud-core/tests/set_properties.rs (new). In `lib.rs` I added `Error::NoSuchBud`, exported `write_frontmatter`, and moved the row insert into a shared helper used by `rescan` and `set_properties`.
Tests:
- Unit tests in frontmatter.rs:
  - replace in place with unknown keys and a comment kept
  - append at the end of the block
  - remove a key with its indented lines
  - no block: create one only when something is set
  - fill an empty block
  - written-format snapshot
  - pinned false is absent
  - CRLF kept
  - awkward values quoted and read back
  - writing what was read changes nothing
- Integration tests in tests/set_properties.rs:
  - one key changes and the body is identical
  - the row follows every property
  - a folder-only bud gets a file, keeps its children, and matches a rescan
  - an unknown path is an error
- Gate, each run from the repository root:
  - `swift build`: passed.
  - `swift test`: passed, 9 tests.
  - `cargo fmt --all --check`: clean.
  - `cargo clippy --all-targets -- -D warnings`: clean.
  - `cargo test --workspace`: passed, 29 tests (15 unit, 10 scan, 4 set_properties).
- I weakened no expectation.
Verify: from the repository root, run `cargo test --workspace`, then read `core/bud-core/tests/set_properties.rs` and the snapshot test `written_formats_snapshot` in `core/bud-core/src/frontmatter.rs`. The commit still has to be made. Subject suggestion: "✨ Write bud frontmatter without touching the rest of the file".
```
