BUILD round 1
Ticket:
- Throwaway crate `core/bud-sync-spike`: met. It has its own `Cargo.toml` with an empty `[workspace]` table, so it is not a workspace member and the gate does not compile it. It loads the fixture vault into one document per bud with each library. It applies 1,000 seeded random body edits, then 100 + 100 concurrent edits on two forks of every document (200 in all), and merges.
- Per-library report: met (table below).
- Table and recommendation: met. They are in `core/bud-sync-spike/README.md`, and the pull request body can copy them verbatim.
- No library added to `bud-core`: met. The root `Cargo.toml` and `bud-core` are untouched.

Results (automerge 0.12, loro 1.17; 11 fixture buds, 287 bytes of body in total):

| Measure | automerge | loro |
| --- | --- | --- |
| Size on disk, fixture after load | 2,954 B | 5,880 B |
| Size on disk after 1,000 edits | 14,596 B | 19,504 B |
| Merge of 200 concurrent edits | 4.38 ms | 0.88 ms |
| Export all bodies as Markdown (median of 9) | 0.260 ms | 0.031 ms |
| Load fixture into documents | 0.88 ms | 0.22 ms |
| 1,000 body edits | 28.9 ms | 1.8 ms |
| Binary size added (release, LTO, size-optimised, stripped; baseline 312,832 B) | 927,160 B | 1,844,880 B |
| Move operation in the tree type | none: there is no tree type, so a move is delete plus insert | yes, `LoroTree::mov` (ran successfully) |

Caveats:
- The fixture is tiny, so the sizes mostly reflect per-document overhead.
- Each timing is a single run on one seed, except export, which is a median.
- The automerge document stores the path in a map and the properties in a map. Only the loro run built a tree document for paths, because automerge has no tree type to build one with.

Recommendation: loro. The paths document needs a move that stays correct under concurrent edits, and only loro has one. Loro is also about 5 to 15 times faster on edit, merge and export. The costs are about 0.9 MB more binary and larger documents on a tiny vault. Re-measure on a larger vault if document growth becomes a worry.

Changed:
- `core/bud-sync-spike/Cargo.toml`
- `core/bud-sync-spike/Cargo.lock`
- `core/bud-sync-spike/README.md`
- `core/bud-sync-spike/src/lib.rs`
- `core/bud-sync-spike/src/bin/baseline.rs`
- `core/bud-sync-spike/src/bin/spike_automerge.rs`
- `core/bud-sync-spike/src/bin/spike_loro.rs`

Tests: This is a measurement spike, so it has no test suite of its own. Both library binaries ran to completion. The automerge and loro Markdown exports of the first document are the same length (466 bytes). Gate from the repo root: `swift build` passed, `swift test` passed (9 tests), `cargo fmt --all --check` clean, `cargo clippy --all-targets -- -D warnings` clean, `cargo test --workspace` passed (55 tests).

Verify:
- From `core/bud-sync-spike`, run `cargo build --release --features automerge,loro`.
- Run `target/release/spike-automerge` and `target/release/spike-loro` to see the timings and sizes.
- Run `ls -l target/release/baseline target/release/spike-automerge target/release/spike-loro` and subtract the baseline size to get the binary size added.
- From the repo root, `cargo build` is unchanged, because the spike is not in the workspace.
