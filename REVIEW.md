REVIEW round 1
Reviewed: crew/BUD-16 against develop
What this does: `Vault::watch` starts a recursive `notify` watcher on the vault folder and returns a `Watch` guard. Dropping the guard stops the watcher and joins its thread. A hand-rolled debounce waits for 300 ms of quiet, capped at 2 s. It then reindexes only the touched paths in one transaction and calls `VaultListener::changed` once per batch. The connection is now `Arc<Mutex<Connection>>`. `set_properties` records the mtime it wrote so the watcher skips that echo. The per-path scan rules (`classify`, `probe`, `is_ignored`, `walk_under`) are shared with the full walk.
Ticket check:
- `Vault::watch`, recursive, stops on drop: met. A test writes a file after `watch` and sees the row.
- 300 ms debounce, coalesced per path, one callback per batch, only touched paths reindexed: met. The burst test gives one callback with five paths. Modify, remove and rename have their own test.
- No echo from the index's own writes: met. `set_properties` records the mtime (`lib.rs:293`) and `reindex_path` skips a matching mtime (`watch.rs:204`). A test covers it.
- Dot folders and non-Markdown files ignored, `.trash/` watched: met. A test covers both.
- The watcher thread never panics on an unreadable event: met. Event errors, per-path failures and a failed commit are logged, and the loop continues. A test removes a folder mid-burst and then confirms a later write is still indexed.
- Beyond the ticket: reconciling a folder bud when `Name.md` appears or goes (`watch.rs:287`). It is tested and fits the scan's rules, so I accept it.
Tests: I ran these from `work`:
- `cargo test --workspace`: passed, with 16 unit, 10 scan, 4 set_properties and 8 watch tests. The watch tests took 1.22 s in total.
- `cargo fmt --all --check`: clean.
- `cargo clippy --all-targets -- -D warnings`: clean.
- `swift build` and `swift test`: not run. The diff touches no Swift, so I rely on the builder's report for them.
- CI: the four required checks passed on `0b90f5f`, per the host's report. No SwiftUI file changed.

Every criterion has a test. The echo test only shows that no batch arrives within 900 ms. It does not show that the watcher saw an event and skipped it. That is acceptable, but the test cannot tell "skipped" from "no event arrived".
Findings:
1. `core/bud-core/src/watch.rs:37` nit: `Drop` joins the watcher thread. If a listener drops its own `Watch` from inside `changed`, the thread joins itself and deadlocks. This is unlikely, but a line in the doc comment on `Watch` would say so.
2. `core/bud-core/src/lib.rs:293` nit: the `written` map is never pruned, so it grows with every distinct file written through `set_properties`. The cost is one small entry per path, so it is not blocking.
3. `core/bud-core/src/watch.rs:204` question (unsure): a stale `written` entry skips any later external edit that lands on the same mtime second. The ticket puts same-second conflicts out of scope, so I take this as accepted behaviour. Please confirm that is the intent.

verdict: approved
