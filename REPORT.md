BUILD round 1
Ticket: all five criteria met.
- `Vault::watch(&self, listener: Box<dyn VaultListener>) -> Result<Watch>`: met. It starts a recursive `notify` watcher on the vault folder, and dropping the returned `Watch` stops the watcher and joins its thread. The test writes a file after `watch` and sees the row.
- 300 ms debounce, coalesced per path, one callback per batch: met. The thread waits for 300 ms of quiet, capped at 2 s for a folder that never goes quiet. It reindexes only the touched paths in one transaction and calls `changed(Vec<String>)` once. The burst test writes five files and gets one callback with five paths. Modify, remove and rename are covered by their own test.
- No echo from the index's own writes: met. `set_properties` records the mtime it wrote, and the watcher skips a file event whose mtime matches. A test covers it.
- Dot folders and non-Markdown files ignored, `.trash/` watched: met. A test covers both.
- The watcher thread never panics on an event it cannot read: met. Event errors, per-path failures and a failed commit are logged to stderr and the loop continues. A test removes a folder mid-burst and then confirms a later write is still indexed.

I also made a file `Name.md` that appears or goes beside a folder bud `Name` move that folder's row and its children's parent. A test covers it.

I implemented the debounce by hand on a channel instead of `notify-debouncer-mini`, so a burst always arrives as one batch.

The callback lists the file paths whose rows changed. A touched folder contributes the paths of the rows below it that changed, not its own path.

Changed:
- `core/bud-core/Cargo.toml`
- `Cargo.lock`
- `core/bud-core/src/lib.rs`: the connection is now `Arc<Mutex<Connection>>`, `Vault` gets a `written` mtime map, and there is a new `watch` method, `Error::Watch`, and a shared `index_found` helper.
- `core/bud-core/src/scan.rs`: the per-path rules are shared with the walk through `classify`, `probe`, `is_ignored` and `walk_under`. `walk` behaves as before.
- `core/bud-core/src/watch.rs` (new)
- `core/bud-core/tests/watch.rs` (new)

Tests:
- I wrote 8 watcher tests in `core/bud-core/tests/watch.rs`.
  - New file shows in the index and the callback.
  - Burst of five files gives one callback.
  - Modify, remove and rename.
  - No echo from the index's own write.
  - Dot folders and non-Markdown files ignored, `.trash/` watched.
  - Folder removed mid-burst.
  - A file beside a folder bud takes its children.
  - Drop stops the watcher.
- Gate, in order:
  - `swift build`: passed.
  - `swift test`: passed, 9 tests.
  - `cargo fmt --all --check`: clean.
  - `cargo clippy --all-targets -- -D warnings`: clean.
  - `cargo test --workspace`: passed. That is 16 unit tests, 10 scan tests, 4 `set_properties` tests and 8 watch tests. The watch tests take about 1.2 s in total.
- I weakened no expectation.

Verify: run `cargo test --workspace` and read `core/bud-core/tests/watch.rs`. To check by hand, open a vault, call `Vault::watch` with a listener, then add, edit, rename or delete `.md` files in the folder from another program. The index rows and the listener callbacks follow about 300 ms after the last change.
