The gate passes and the work is complete. Here is the review.

```
REVIEW round 1
Reviewed: crew/BUD-18 against develop
What this does: Adds a small fictional Obsidian vault fixture under `core/bud-core/tests/fixtures/obsidian/`. Adds `core/bud-core/tests/obsidian.rs` with 8 tests that open and rescan it and check the indexed rows, the skipped files, the trash, the folder note, the wiki links and the unchanged bytes. No source changes, since the crate already behaves this way.
Ticket check: fixture tree (`.obsidian/app.json` and `workspace.json`, `Daily/` with dated notes, frontmatter with tags and aliases, wiki links and embed, `image.png`, `Projects/Projects.md`, `Templates/`, `.trash/` with one file): met. Every .md is a note with no state, folders are buds, `.obsidian/` and the png are skipped, `.trash/` is trash: met (full row list asserted). Bytes identical after open, rescan, search, today and counts, checked by hashing every file before and after: met. `Projects/Projects.md` is a child of `Projects`, stated explicitly in the test: met. Wiki links stay as text in `body`, exact body asserted: met. Beyond the ticket: nothing.
Tests: I ran `cargo test --workspace` from `work` and it passed, including the 8 new tests in `obsidian.rs`. The one ignored test is the existing 5000-bud timing test. `cargo clippy --workspace --all-targets -- -D warnings` was clean and `cargo fmt --all --check` was clean. `swift build` passed and `swift test` passed with 13 tests; no Swift files changed. The host's checks on 5cfd79d97a509ef7172a5912b1bf2da0f59d25cf passed (5 checks), so the four required checks are covered. The diff touches no SwiftUI file. Gap: the frontmatter test does not assert the tags or aliases, which fits the out-of-scope line, since only the note and its body are checked.
Findings:
1. core/bud-core/tests/obsidian.rs:21 nit: `DefaultHasher` has no stability guarantee across Rust releases. This is harmless because both hashes are computed in the same process, but comparing the raw bytes would remove the doubt.
2. core/bud-core/tests/fixtures/obsidian/image.png:1 nit: the file is text, not a PNG. The scan skips it by extension, so the tests don't depend on its bytes, but a fixture meant to look like a real vault would use a tiny real PNG.
3. The fixture has no personal data, and the hard rules are not broken. The only changes are a new test and its fixtures, and no forbidden path is touched.
verdict: approved
```
