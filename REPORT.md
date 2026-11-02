BUILD round 1
Ticket: all six criteria are met, with the choices below flagged for the reviewer.
- `Vault::search(query, limit) -> Vec<Hit { path, title, trail, snippet }>`: met.
  - FTS5 external-content table `buds_fts` over `title` and `body`. Triggers on `buds` keep it in sync with the scan, every write, the watcher and trash/restore. `insert_row` is now an upsert instead of `INSERT OR REPLACE`, so a row keeps its rowid.
  - Title hits come first, then body hits, each ranked by bm25 with the title weighted 10 to 1. Prefix matching applies to the last word. Words are quoted, so FTS syntax in a query is plain text.
  - Trash is left out. Inbox and Archive are included.
  - Tests cover "lis" and the two-word "welcome lis".
- `Vault::today(date)`: met. Open to-dos with `due <= date` come first, by `due`. Then those with `when <= date` and not already listed, by `when`. Dates are compared on their first 10 characters. Each row has its trail.
- `Vault::counts(path) -> Counts { inside, open_todos }`: met. A recursive CTE counts all descendants, including folder-only buds. Tested on a three-level tree.
- `Vault::next_step(under, date)`: met. It orders by soonest `due`, then soonest `when`, then oldest `created`, with missing values last. Tests cover four orderings plus the `under` scope. Done to-dos, notes and Trash are skipped.
  - `date` is accepted but unused (`_date`). An overdue to-do already sorts first, so the order doesn't depend on it.
- `Vault::lens(Lens::Todos | Lens::Pinned)`: met, with trails. Todos means open to-dos in the same order as `next_step`. Pinned is ordered by `created`, then title. Trash is excluded from both.
- Under 20 ms on 5,000 buds: met. Release-mode run of the ignored benchmark `each_query_runs_under_20_ms_on_5000_buds`:

  | Query | Time |
  |---|---|
  | search "lis" | 0.81 ms |
  | search, two words | 1.04 ms |
  | today | 1.47 ms |
  | counts | 0.27 ms |
  | next_step, whole vault | 0.29 ms |
  | next_step, under a bud | 0.44 ms |
  | lens Todos | 11.4 ms (about 1,700 rows) |
  | lens Pinned | 0.83 ms |

Decisions for the reviewer:
- Trails are computed in SQL with a recursive CTE on `parent`, run per result row. They hold ancestor titles, root first, and leave out the bud itself.
- Only Trash is excluded from `today`, `next_step` and the lenses. Archive is not. Say if Archive should be excluded too.
- `SCHEMA_VERSION` went from 1 to 2, so an existing index is rebuilt on open and the next rescan refills it.
- `Row` and `Counts` have no hand-written `Default` or serde derives, and no Swift or UniFFI surface is added. The ticket asked only for the Rust API.

Changed:
- `core/bud-core/src/lib.rs`
- `core/bud-core/src/query.rs` (new)
- `core/bud-core/src/schema.sql`
- `core/bud-core/tests/query.rs` (new)

Tests:
- `core/bud-core/tests/query.rs` has 14 tests and one ignored benchmark.
  - Search: prefix, two words, limit and odd input, following create/set_body/rename/trash/restore, and following a rescan of edited and removed files.
  - Today: ordering, and an early date giving an empty list.
  - Counts: the three-level tree.
  - Next step: four orderings, a due tie, and the `under` scope.
  - Lenses: Todos and Pinned.
- `cargo test --workspace` passes: 77 tests, with 1 ignored benchmark in the new file. The 62 existing tests are unchanged and pass.
- `cargo fmt --all --check` is clean. `cargo clippy --all-targets -- -D warnings` is clean.
- `swift build` and `swift test` pass (10 tests).

Verify:
- Run `cargo test --workspace` from the repo root.
- To reproduce the timing, run `cargo test --release -p bud-core --test query -- --ignored --nocapture`.
- By hand, open a vault, call `rescan`, then `search("lis", 10)`. Rename or trash a bud and search again to see the index follow.
