BUILD round 2

Applied:
- Finding 1 (outside edit lost when remote edits arrive before `sync`): `merge_doc` in `core/bud-core/src/sync.rs` now applies the outside edit to the document before importing the remote bytes, and stores the file text as the known text. The remote edit now merges with the outside edit instead of deleting it. A new test, `an_outside_edit_not_yet_synced_survives_a_merge_of_remote_edits` in `core/bud-core/tests/sync.rs`, covers it. It edits a file outside on one replica, imports the other replica's text and property edits without running `sync`, and checks both edits are in the file and a later sync writes nothing. I did not run that test against the old code, so I have not seen it fail there.
- Finding 2 (identities are random per replica): the contract is now stated in the module doc of `core/bud-core/src/sync.rs`. A replica takes over another's identities with `adopt_doc` and `merge_tree` before it syncs on its own. I did not make the ids deterministic.

Declined:
- Finding 2, deterministic ids: the reviewer said this alone does not block. Ids derived from the path would give two replicas separate histories of the same text, so the merged file would hold the text twice. The handoff is the safe contract.
- Finding 3 (a file renamed outside the app gets a new identity): this is intended for this ticket. A scan sees a removed path and a new path, and matching them would need content tracking that the ticket does not ask for. The limit is written in the module doc.

Tests:
- `cargo fmt --all --check`: clean.
- `cargo clippy --all-targets -- -D warnings`: clean.
- `cargo test --workspace`: all passed, including 11 tests in `core/bud-core/tests/sync.rs` and `the_vault_is_never_written`.
- `swift build`: complete.
- `swift test`: 42 passed.
