REVIEW round 2
Earlier findings:
1. Outside edit lost when a merge arrives before `sync` (`core/bud-core/src/sync.rs`): addressed. `merge_doc` now applies the outside edit to the document before importing the remote bytes, so the document still holds what the file was diffed from. It then stores the file text as the known text. The new test `an_outside_edit_not_yet_synced_survives_a_merge_of_remote_edits` checks that both the outside edit and the remote edit end up in the file and that a later sync writes nothing. The builder did not run it against the old code. By my reading of the old `merge_doc`, it would fail there.
2. Random per-replica identities: addressed as a documented contract. Declining deterministic ids is reasonable, since path-derived ids would give each replica its own history of the same text. The identity contract is now in the module doc.
3. A file renamed outside the app gets a new identity: accepted decline. The limit is written in the module doc.
New: nothing. The change is limited to `merge_doc`, the module doc and the new test.
Tests: The host's checks on the head passed (5 checks); I read that and did not rerun them. I ran the box gate from the repo root:
- `swift build`: complete.
- `swift test`: 42 passed.
- `cargo fmt --all --check`: clean.
- `cargo clippy --all-targets -- -D warnings`: clean.
- `cargo test --workspace`: all passed, including 11 tests in `tests/sync.rs` and `the_vault_is_never_written`.

The diff since the last round touches no SwiftUI file.
verdict: approved
