Fmt, clippy, `cargo test --workspace` and `swift test` all pass on my run. I'm writing the verdict now.

REVIEW round 1
Reviewed: crew/BUD-17 against develop
What this does: Adds `core/bud-core/src/query.rs` with `Vault::search`, `today`, `counts`, `next_step` and `lens`. Search uses an FTS5 external-content table, `buds_fts`, kept in sync by triggers on `buds`. `insert_row` becomes an upsert so rows keep their rowid, and `SCHEMA_VERSION` goes to 2 so old indexes are rebuilt. Trails are computed in SQL with a recursive CTE per result row, and the report says so.
Ticket check:
- search (title hits first, last-token prefix, Trash out, Inbox in): met.
- today: met.
- counts (recursive CTE): met.
- next_step: met. `_date` is unused, which the report states.
- lens(Todos | Pinned): met.
- 20 ms on 5,000 buds: met. The report gives timings from the ignored benchmark, with the largest at 11.4 ms for lens Todos. I did not rerun it.
- Beyond the ticket: none.
Tests:
- `core/bud-core/tests/query.rs` has 14 tests and 1 ignored benchmark. They cover "lis" and a two-word query, index follow-up after writes and rescan, today ordering, counts on a three-level tree, four next_step orderings plus the `under` scope, and both lenses with trails.
- I ran `cargo fmt --all --check` (clean), `cargo clippy --all-targets -- -D warnings` (clean) and `cargo test --workspace` (all pass, benchmark ignored). I also ran `swift test` (10 pass).
- CI: the host's checks on the head, 5 in all, passed. The diff touches no SwiftUI file.
Findings:
1. core/bud-core/src/query.rs:~165 nit: `next_step` accepts `date` but ignores it. The ordering is correct without it, so this is harmless, but it is worth keeping the parameter only if the app will need it.
2. core/bud-core/src/lib.rs:~418 nit: `pub(crate) const SELECT: &str ="SELECT ...` is missing a space after `=`. Neither rustfmt nor clippy flags it, so it is cosmetic.
3. core/bud-core/src/query.rs, question: Archive is not excluded from `today`, `next_step` or the lenses, and the report asks about it. The ticket only says to leave Trash out, so I read this as acceptable. The operator can confirm.

```
verdict: approved
```
