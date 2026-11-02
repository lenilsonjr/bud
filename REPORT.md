BUILD round 1
Ticket: all eight criteria met.
- `Vault::create` is met. It writes `<parent folder>/<title>.md` with `created` now, `state: open` for a to-do, `source` when given, and an empty body. The parent is the root for `None`, `Inbox` or `Archive` for a place, or a bud's path, whose folder is created if missing. A taken name gets " 2", " 3". A name counts as taken if a file or a folder has it. An unknown parent bud is `Error::NoSuchBud`. Tests cover root, nested, inbox, collision, and a title cleaned for use as a filename.
- `Vault::set_body` is met. It keeps the frontmatter byte for byte. A folder-only bud gets its `.md` file first, as `set_properties` already does.
- `Vault::rename` is met. It renames the file and its sibling folder together and rewrites every descendant row's `path`, `parent` and `title`. The test uses a three-level tree. Renaming onto a name that is taken is a new `Error::Exists`.
- `Vault::move_to` is met. The moved bud's sibling folder and descendants follow. Moving into itself or a descendant is a new `Error::Invalid`. Landing on a taken name is `Error::Exists`. `Inbox` and `Archive` work as targets, and `None` moves to the root.
- `Vault::trash` and `Vault::restore` are met.
  - `trash` moves the file and folder to `.trash/<same relative path>` and sets `place = trash`.
  - It also adds rows for the intermediate trash folders, so the index matches what a rescan finds.
  - `restore` moves everything back and returns the new path.
  - It removes the trash folders it empties, and refuses a path outside the trash.
- `Vault::set_state` and `Vault::set_pinned` are met. They go through `set_properties`, and a test shows a done parent leaves its child's file and row untouched.
- Atomic writes and failed moves are met. Writes go to a temp file in the same folder and are then renamed, and `set_properties` now uses the same writer.
  - Files move before the index changes. If a file moves but its sibling folder cannot, the file is moved back.
  - The failure test makes the target folder read-only for both a move and a rename, then asserts the rows and the files are unchanged.
- Filenames are met. `sanitize_filename` replaces `/ \ : * ? " < > |`, control characters and leading dots with a space, trims, and returns "Untitled" when nothing is left. It is exported and unit tested.

Changed:
- `core/bud-core/src/edit.rs` (new)
- `core/bud-core/src/lib.rs`
- `core/bud-core/src/scan.rs` (a few helpers made `pub(crate)`)
- `core/bud-core/tests/edit.rs` (new)

Tests:
- I wrote `tests/edit.rs` with 22 tests and added a unit test for the date formatter.
- Most of the edit tests also check that the index equals what a fresh rescan produces, ignoring mtime.
- Gate: `swift build` passed, `swift test` passed (9 tests), `cargo fmt --all --check` was clean, `cargo clippy --all-targets -- -D warnings` was clean, and `cargo test --workspace` passed (17 unit, 22 edit, 10 scan, 4 set_properties).
- I did not weaken any expectation.

Verify:
- Run `cargo test --workspace`.
- To check by hand, open a vault, call `create(Some("Inbox"), "Idea", Kind::Todo, None)`, then `rename`, `move_to`, `trash` and `restore` on a bud that has children. Compare the folder with `vault.all()` after each call, and call `rescan()` to confirm it reports no change.
