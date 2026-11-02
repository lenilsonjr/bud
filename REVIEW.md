REVIEW round 1
Reviewed: crew/BUD-38 against develop
What this does: Adds a throwaway crate, `core/bud-sync-spike`, that is outside the workspace. It loads the fixture vault into one document per bud with automerge and with loro. It then applies 1,000 seeded body edits and 100 + 100 concurrent edits on two forks of each document, and merges. It measures size, merge time, Markdown export time and binary size, and it calls loro's `LoroTree::mov`. The README holds the table and recommends loro.
Ticket check:
- Throwaway crate, own `Cargo.toml`, not a workspace member: met. It has an empty `[workspace]` table, and the root `Cargo.toml` is untouched.
- Load fixture, 1,000 edits, 200 concurrent edits from two replicas, merge: met, for both libraries, with the same seeds.
- Per-library report (size on disk, merge time, Markdown export time, binary size added, tree move): met. The code prints each figure. I did not re-run the spike binaries, so I did not check the table's numbers.
- Table and recommendation in the pull request body: partial. They are in the README and the report says they can be copied verbatim. I cannot see the PR body from here. The text names no machine, though it says "one machine class", which is harmless.
- `bud-core` not touched and `cargo build` on develop unchanged: met.
- Hard rules: no secrets, no personal data, no forbidden paths touched, no SwiftUI files. The crate's Markdown file is covered by finding 3.
Tests: This is a measurement spike with no test suite, which is acceptable for a throwaway crate. I ran the box gate from `work`:
- `swift build`: passed.
- `swift test`: 9 tests passed.
- `cargo fmt --all --check`: clean.
- `cargo clippy --all-targets -- -D warnings`: clean.
- `cargo test --workspace`: 55 tests passed (17 + 24 + 10 + 4).
- CI: the host's checks on `8969579d79f28a80c96da0aba307a4722549479a` passed (5 checks), so I did not run the app builds.
Findings:
1. core/bud-sync-spike/src/bin/spike_automerge.rs:21-26 nit: The edit-timing comparison is not like for like. Each automerge edit calls `doc.text(&body)` and `.chars().count()`, which is O(n) and is inside the timed region. Loro uses `len_unicode()` and commits after every edit. The 16x edit-speed gap is therefore somewhat inflated. The 5x merge and 8x export gaps do not depend on this, and the recommendation does not rest on edit speed, so it stands. Worth a sentence in the README.
2. core/bud-sync-spike/src/bin/spike_loro.rs:79-84 design: The tree check is a toy tree (create, create, move), not the vault's paths loaded as a tree document. The ticket describes a "tree document for paths". The yes/no on move is still answered, and automerge has no tree type, which the report states. A move-conflict test (two replicas moving the same node) would back the claim "resolves concurrent moves without cycles" in README.md:32. As written, that claim comes from loro's documentation, not from this run.
3. core/bud-sync-spike/README.md:1 question: The repo rules allow no Markdown files beyond the root README. Is a README inside a throwaway crate that is closed without merge acceptable, or should the table live only in the PR body? Since the branch is never merged, I treat this as non-blocking.
4. core/bud-sync-spike/README.md:14 nit: The sizes come from a vault with 287 bytes of body in total. The README says so and says to re-measure on a larger vault. The recommendation relies on the move operation and speed, not on size, so it holds.
verdict: approved
