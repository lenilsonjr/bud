REVIEW round 1
Reviewed: crew/BUD-14 against develop

What this does: Adds `frontmatter::write`, a line-based editor for the six known keys. It replaces a key in place, appends a missing one, removes a `None` key, and creates a block only when something is set. Adds `Vault::set_properties`, which writes `<name>.md.tmp`, renames it into place, and updates the index row. A folder-only bud gets `Name.md` created beside the folder, and its children are re-parented to the file.

Ticket check:
- Properties parse and `write(text, &Properties)`: partial. Replace, append, remove, no-block and unknown-key survival all work. A key whose value is already right is still rewritten, and that loses user formatting (finding 1).
- `set_properties` atomic write, row update and folder-only bud: met. A test asserts the body is unchanged, and the folder case matches a rescan.
- Written formats: met. `written_formats_snapshot` covers them.
- No reformatting of user YAML outside the touched keys: partial. Comments on their own lines, unknown keys and CRLF survive. Quotes and trailing comments on the known keys do not (finding 1).
- Goal "setting `state` writes exactly one key": not met when other known keys carry quotes or trailing comments (finding 1).

Tests:
- I ran the gate from `work`:
  - `swift build`: passed.
  - `swift test`: 9 tests passed.
  - `cargo fmt --all --check`: clean.
  - `cargo clippy --all-targets -- -D warnings`: clean.
  - `cargo test --workspace`: 15 unit, 10 scan and 4 set_properties tests passed.
- The host's checks on `cb8b710` passed (4 checks). I did not re-run them.
- Gap: no test has a known key with a quoted value or a trailing comment, other than the one that is changed. `writing_what_is_read_changes_nothing` and the integration fixture use only plain values. That is why finding 1 passes the suite.

Findings:
1. core/bud-core/src/frontmatter.rs:177-193 (`edit_block`) bug: Every known key already in the block is rewritten from its parsed value, even when the value is unchanged. `set_properties` always passes all six properties. Take `---\nsource: "phone"\nstate: open # check\n---`. Setting only `state` to done rewrites `source: "phone"` as `source: phone`. The `# check` comment is lost, and `state: open # check` becomes `state: done`. The same happens to `pinned: yes` or `True` (written as `true`), to quoted dates, and to a continuation of a multi-line value. This breaks the Goal ("writes exactly one frontmatter key") and the MUST NOT ("quotes, comments"). Fix: for each key present in the file, parse the existing value text with the same logic as `parse`. If it already equals the wanted value, keep the original lines (and any indented continuation) untouched. Rewrite only when the value differs, and when it does, consider keeping a trailing comment. Add a test where a quoted or commented known key survives a change to a different key.
2. core/bud-core/src/lib.rs:263 (`set_properties`) nit: `std::fs::write` to the `.tmp` file is not synced before the rename. Atomic by rename is what the ticket asks for, so this does not block.
3. core/bud-core/src/lib.rs:233-290 (`set_properties`) question: The file is read with `read_to_string` and then written back. Is it intended that a file with invalid UTF-8 is refused with an `Io` error? That is safe, so no change is needed unless you want a clearer error.

verdict: changes requested
